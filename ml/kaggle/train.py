"""
Pelatihan pengenal hidangan Indonesia (13 kelas) di Kaggle. Artefak pelatihan, bukan service di repo/compose.
Keluaran (/kaggle/working): model.pt (state_dict), classes.json, metrics.json, report.md, split_audit.json.
Hanya mengenali NAMA hidangan dari foto. Tidak menebak kalori atau porsi. Status model: RESEARCH_ONLY.
"""
import hashlib, json, os, random, time
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from PIL import Image, ImageFile
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms

ImageFile.LOAD_TRUNCATED_IMAGES = True
SEED = 1337
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)
OUT = Path("/kaggle/working"); OUT.mkdir(exist_ok=True, parents=True)

root = next(p for p in Path("/kaggle/input").rglob("dataset_gambar") if p.is_dir())
splits = {s: root / s for s in ("train", "valid", "test")}
for s, p in splits.items():
    assert p.exists(), f"split {s} tidak ada di {root}"
classes = sorted(d.name for d in splits["train"].iterdir() if d.is_dir())
cidx = {c: i for i, c in enumerate(classes)}
EXT = {".jpg", ".jpeg", ".png", ".webp"}

def listing(split):
    items = []
    for c in classes:
        for f in sorted((splits[split] / c).glob("*")):
            if f.suffix.lower() in EXT:
                items.append((f, cidx[c]))
    return items

data = {s: listing(s) for s in splits}
print({s: len(v) for s, v in data.items()}, "classes", len(classes))

# ---- Audit kebocoran: hash berkas persis + dHash perseptual antar split -------------------------------------------------
def dhash(path, size=8):
    try:
        im = Image.open(path).convert("L").resize((size + 1, size), Image.LANCZOS)
    except Exception:
        return None
    a = np.asarray(im, dtype=np.int16)
    bits = (a[:, 1:] > a[:, :-1]).flatten()
    return int("".join("1" if b else "0" for b in bits), 2)

def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()

hashes = {s: [(p, y, dhash(p), md5(p)) for p, y in items] for s, items in data.items()}
train_md5 = {m for _, _, _, m in hashes["train"]}
train_dh = [(d, y) for _, y, d, _ in hashes["train"] if d is not None]
def ham(a, b): return bin(a ^ b).count("1")
audit = {}
leak = {}
for s in ("valid", "test"):
    exact = near = 0
    keep = []
    for p, y, d, m in hashes[s]:
        is_exact = m in train_md5
        is_near = (not is_exact) and d is not None and any(ham(d, td) <= 3 for td, _ in train_dh)
        exact += is_exact; near += is_near
        if not (is_exact or is_near):
            keep.append((p, y))
    audit[s] = {"total": len(hashes[s]), "exact_dup_of_train": exact, "near_dup_of_train(<=3 bits)": near, "clean": len(keep)}
    leak[s] = keep
within = Counter(m for _, _, _, m in hashes["train"])
audit["train_internal_exact_duplicates"] = sum(v - 1 for v in within.values() if v > 1)
audit["class_counts"] = {s: dict(Counter(classes[y] for _, y in data[s])) for s in data}
json.dump(audit, open(OUT / "split_audit.json", "w"), indent=2, ensure_ascii=False)
print(json.dumps(audit, indent=2, ensure_ascii=False)[:1500])

# ---- Data & model -------------------------------------------------------------------------------------------------------
dev = "cuda" if torch.cuda.is_available() else "cpu"
mean, std = [0.485, 0.456, 0.406], [0.229, 0.224, 0.225]
tr_t = transforms.Compose([transforms.RandomResizedCrop(224, scale=(0.6, 1.0)), transforms.RandomHorizontalFlip(), transforms.ColorJitter(0.2, 0.2, 0.2), transforms.ToTensor(), transforms.Normalize(mean, std)])
ev_t = transforms.Compose([transforms.Resize(256), transforms.CenterCrop(224), transforms.ToTensor(), transforms.Normalize(mean, std)])

class DS(Dataset):
    def __init__(self, items, tf): self.items, self.tf = items, tf
    def __len__(self): return len(self.items)
    def __getitem__(self, i):
        p, y = self.items[i]
        try:
            im = Image.open(p).convert("RGB")
        except Exception:
            im = Image.new("RGB", (224, 224))
        return self.tf(im), y

def loader(items, tf, shuffle): return DataLoader(DS(items, tf), batch_size=64, shuffle=shuffle, num_workers=2, pin_memory=True)
dl_tr, dl_va = loader(data["train"], tr_t, True), loader(data["valid"], ev_t, False)
dl_te, dl_te_clean = loader(data["test"], ev_t, False), loader(leak["test"], ev_t, False)

try:
    net = models.mobilenet_v3_large(weights=models.MobileNet_V3_Large_Weights.IMAGENET1K_V2)
    pretrained = "ImageNet-1k (torchvision MobileNet_V3_Large IMAGENET1K_V2)"
except Exception as e:  # tanpa internet: latih dari awal dan laporkan
    print("bobot pralatih tidak tersedia:", repr(e)[:120])
    net = models.mobilenet_v3_large(weights=None)
    pretrained = "NONE (dilatih dari awal; bobot pralatih tidak dapat diunduh)"
net.classifier[3] = nn.Linear(net.classifier[3].in_features, len(classes))
net.to(dev)
crit = nn.CrossEntropyLoss(label_smoothing=0.1)
EPOCHS = 8
opt = torch.optim.AdamW(net.parameters(), lr=1e-3 if pretrained.startswith("NONE") else 3e-4, weight_decay=1e-4)
sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=opt.param_groups[0]["lr"] * 3, total_steps=EPOCHS * len(dl_tr))

def evaluate(dl):
    net.eval(); logits, ys = [], []
    with torch.no_grad():
        for x, y in dl:
            logits.append(net(x.to(dev)).float().cpu()); ys.append(y)
    return torch.cat(logits), torch.cat(ys)

best, best_state, history = 0.0, None, []
t0 = time.time()
for ep in range(EPOCHS):
    net.train(); run = 0.0
    for x, y in dl_tr:
        x, y = x.to(dev), y.to(dev)
        opt.zero_grad(); loss = crit(net(x), y); loss.backward(); opt.step(); sched.step(); run += loss.item() * len(y)
    lg, ys = evaluate(dl_va); acc = (lg.argmax(1) == ys).float().mean().item()
    history.append({"epoch": ep + 1, "train_loss": run / len(data["train"]), "valid_acc": acc})
    print(history[-1], flush=True)
    if acc > best: best, best_state = acc, {k: v.detach().cpu().clone() for k, v in net.state_dict().items()}
net.load_state_dict(best_state)

# ---- Kalibrasi suhu pada valid, evaluasi pada test (penuh dan bersih dari duplikat) ----------------------------------------
lg_va, y_va = evaluate(dl_va)
T = torch.nn.Parameter(torch.ones(1))
o = torch.optim.LBFGS([T], lr=0.1, max_iter=100)
def nll():
    o.zero_grad(); l = nn.functional.cross_entropy(lg_va / T, y_va); l.backward(); return l
o.step(nll); temp = float(T.detach())

def ece(logits, ys, t, bins=10):
    p = torch.softmax(logits / t, 1); conf, pred = p.max(1); ok = (pred == ys).float()
    e = 0.0
    for b in range(bins):
        lo, hi = b / bins, (b + 1) / bins
        m = (conf > lo) & (conf <= hi)
        if m.any(): e += m.float().mean().item() * abs(ok[m].mean().item() - conf[m].mean().item())
    return e

def report(dl, name):
    lg, ys = evaluate(dl); pred = lg.argmax(1)
    acc = (pred == ys).float().mean().item()
    per = {}
    for i, c in enumerate(classes):
        tp = ((pred == i) & (ys == i)).sum().item(); fp = ((pred == i) & (ys != i)).sum().item(); fn = ((pred != i) & (ys == i)).sum().item()
        pr = tp / (tp + fp) if tp + fp else 0.0; rc = tp / (tp + fn) if tp + fn else 0.0
        per[c] = {"precision": round(pr, 4), "recall": round(rc, 4), "f1": round(2 * pr * rc / (pr + rc), 4) if pr + rc else 0.0, "support": int((ys == i).sum())}
    cm = torch.zeros(len(classes), len(classes), dtype=torch.int64)
    for t, p in zip(ys, pred): cm[t, p] += 1
    top3 = (lg.topk(3, 1).indices == ys[:, None]).any(1).float().mean().item()
    return {"split": name, "n": len(ys), "accuracy": round(acc, 4), "top3_accuracy": round(top3, 4), "ece_raw": round(ece(lg, ys, 1.0), 4), "ece_calibrated": round(ece(lg, ys, temp), 4), "per_class": per, "confusion_matrix": cm.tolist()}

m_full, m_clean = report(dl_te, "test_full"), (report(dl_te_clean, "test_deduplicated") if len(leak["test"]) else None)
metrics = {"model": "mobilenet_v3_large", "pretrained": pretrained, "epochs": EPOCHS, "seed": SEED, "temperature": round(temp, 4), "best_valid_acc": round(best, 4), "train_seconds": round(time.time() - t0), "classes": classes, "history": history, "test_full": m_full, "test_deduplicated": m_clean, "audit": audit,
           "limitations": ["Dataset hasil scraping; lisensi tidak tercantum di metadata Kaggle (RESEARCH_ONLY).", "13 hidangan, termasuk pizza/burger/french fries yang kurang relevan.", "Akurasi pada foto pengguna nyata TIDAK diketahui.", "Hanya nama hidangan; bukan kalori atau porsi."]}
json.dump(metrics, open(OUT / "metrics.json", "w"), indent=2, ensure_ascii=False)
json.dump({"classes": classes, "temperature": temp, "input_size": 224, "mean": mean, "std": std}, open(OUT / "classes.json", "w"), ensure_ascii=False)
torch.save(net.state_dict(), OUT / "model.pt")
sha = hashlib.sha256(open(OUT / "model.pt", "rb").read()).hexdigest()
(OUT / "report.md").write_text(f"""# Pengenal hidangan Indonesia — laporan evaluasi
- Arsitektur: MobileNetV3-Large, bobot awal: {pretrained}
- Data: train {len(data['train'])} / valid {len(data['valid'])} / test {len(data['test'])}; {len(classes)} kelas
- Audit kebocoran: {json.dumps(audit['valid'])} (valid), {json.dumps(audit['test'])} (test)
- Valid acc terbaik: {best:.4f}; suhu kalibrasi: {temp:.3f}
- Test penuh: acc {m_full['accuracy']}, top3 {m_full['top3_accuracy']}, ECE mentah {m_full['ece_raw']} → terkalibrasi {m_full['ece_calibrated']}
- Test tanpa duplikat: {('acc ' + str(m_clean['accuracy']) + ' (n=' + str(m_clean['n']) + ')') if m_clean else 'tidak ada'}
- SHA-256 model.pt: {sha}
- Status: RESEARCH_ONLY. Lihat metrics.json untuk batasan.
""")
print("DONE", sha, m_full["accuracy"], (m_clean or {}).get("accuracy"))
