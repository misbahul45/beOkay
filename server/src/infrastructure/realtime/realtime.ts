import { RedisClient, type Server, type ServerWebSocket } from "bun";
import { prisma } from "../database/prisma.ts";

export type SocketData = { userId: string; sessionId: string; topics: Set<string>; checkedAt: number };
export type RealtimeEvent = { type: string; [key: string]: unknown };
export type TopicGuard = (userId: string, topic: string) => Promise<boolean>;

const RECHECK_MS = 60_000;
const MAX_TOPICS = 20;
let server: Server<SocketData> | null = null;
let guard: TopicGuard = async () => false;
const sockets = new Map<string, number>();

const send = (ws: ServerWebSocket<SocketData>, event: RealtimeEvent): void => {
  ws.send(JSON.stringify(event));
};

async function sessionAlive(data: SocketData) {
  const s = await prisma.sessions.findUnique({ where: { id: data.sessionId }, select: { userId: true, expiresAt: true } });
  return Boolean(s && s.userId === data.userId && s.expiresAt.getTime() > Date.now());
}

const BUS_CHANNEL = "beokay:realtime";
const instance = crypto.randomUUID();
let bus: RedisClient | null = null;

function local(channel: string, data: string) {
  server?.publish(channel, data);
}

function fanout(channel: string, data: string) {
  local(channel, data);
  bus?.publish(BUS_CHANNEL, JSON.stringify({ o: instance, c: channel, d: data })).catch(() => {});
}

export const realtime = {
  attach(s: Server<SocketData>) {
    server = s;
  },
  async connectBus(url: string) {
    const pub = new RedisClient(url);
    const sub = new RedisClient(url);
    await sub.subscribe(BUS_CHANNEL, (message) => {
      try {
        const m = JSON.parse(message) as { o: string; c: string; d: string };
        if (m.o !== instance && typeof m.c === "string" && typeof m.d === "string") local(m.c, m.d);
      } catch {
        return;
      }
    });
    bus = pub;
  },
  setTopicGuard(g: TopicGuard) {
    guard = g;
  },
  toUser(userId: string, event: RealtimeEvent) {
    fanout(`user:${userId}`, JSON.stringify(event));
  },
  toTopic(topic: string, event: RealtimeEvent) {
    fanout(topic, JSON.stringify(event));
  },
  connections(userId: string) {
    return sockets.get(userId) ?? 0;
  },
  onOpen: null as ((ws: ServerWebSocket<SocketData>) => Promise<void>) | null,
};

export const websocket = {
  idleTimeout: 120,
  maxPayloadLength: 4096,
  async open(ws: ServerWebSocket<SocketData>) {
    ws.subscribe(`user:${ws.data.userId}`);
    sockets.set(ws.data.userId, (sockets.get(ws.data.userId) ?? 0) + 1);
    if (realtime.onOpen) await realtime.onOpen(ws);
  },
  async message(ws: ServerWebSocket<SocketData>, raw: string | Buffer) {
    if (Date.now() - ws.data.checkedAt > RECHECK_MS) {
      ws.data.checkedAt = Date.now();
      if (!(await sessionAlive(ws.data))) {
        ws.close(4401, "SESSION_ENDED");
        return;
      }
    }
    let msg: { type?: unknown; topic?: unknown };
    try {
      msg = JSON.parse(String(raw));
    } catch {
      send(ws, { type: "error", code: "BAD_MESSAGE" });
      return;
    }
    if (msg.type === "ping") return send(ws, { type: "pong", at: new Date().toISOString() });
    const topic = typeof msg.topic === "string" ? msg.topic : "";
    if (msg.type === "subscribe") {
      if (!/^challenge:[0-9a-f-]{36}$/.test(topic) || ws.data.topics.size >= MAX_TOPICS || !(await guard(ws.data.userId, topic))) {
        return send(ws, { type: "error", code: "TOPIC_FORBIDDEN", topic });
      }
      ws.subscribe(topic);
      ws.data.topics.add(topic);
      return send(ws, { type: "subscribed", topic });
    }
    if (msg.type === "unsubscribe" && ws.data.topics.has(topic)) {
      ws.unsubscribe(topic);
      ws.data.topics.delete(topic);
      return send(ws, { type: "unsubscribed", topic });
    }
    send(ws, { type: "error", code: "UNKNOWN_MESSAGE" });
  },
  close(ws: ServerWebSocket<SocketData>) {
    const n = (sockets.get(ws.data.userId) ?? 1) - 1;
    if (n <= 0) sockets.delete(ws.data.userId);
    else sockets.set(ws.data.userId, n);
  },
};
