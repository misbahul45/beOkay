import type { Prisma } from "../../generated/prisma/client.ts";
import { prisma } from "../../infrastructure/database/prisma.ts";
export type NutritionDb = Prisma.TransactionClient;
export const mealInclude = {items:{orderBy:{id:"asc" as const}}} as const;
export const nutritionRepository = {
  food(userId:string,id:string,db:NutritionDb=prisma) { return db.foodCatalog.findFirst({where:{id,OR:[{userId},{userId:null}]}}); },
  meal(userId:string,id:string,db:NutritionDb=prisma) { return db.mealLog.findFirst({where:{id,userId},include:mealInclude}); },
  async dateIds(userId:string,date:string,timezone:string,db:NutritionDb=prisma) {
    const rows=await db.$queryRaw<{id:string}[]>`SELECT id FROM meal_logs WHERE user_id=${userId}::uuid AND archived_at IS NULL AND consumed_at >= (${date}::date::timestamp AT TIME ZONE ${timezone}) AND consumed_at < ((${date}::date + 1)::timestamp AT TIME ZONE ${timezone})`;
    return rows.map(row=>row.id);
  },
};
