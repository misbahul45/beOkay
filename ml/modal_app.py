"""
Endpoint inferensi pengenal hidangan di Modal. Artefak deploy, BUKAN service di compose.
Artefak model ada di Modal Volume `beokay-models` pada /dish/<versi>/{model.pt,classes.json}; `current.json` menunjuk versi aktif dan
memuat SHA-256 yang diverifikasi saat memuat model. Hanya mengenali NAMA hidangan; tidak menebak kalori atau porsi.
Autentikasi: bearer token dari Modal Secret `beokay-ml-auth` (ML_AUTH_TOKEN), dibandingkan dengan waktu konstan.
"""
import base64, hashlib, hmac, io, json, os, time

import modal

app = modal.App("beokay-dish-classifier")
VOL = modal.Volume.from_name("beokay-models", create_if_missing=True)
IMAGE = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install("torch==2.4.1", "torchvision==0.19.1", "pillow==10.4.0", "fastapi[standard]==0.115.0", extra_index_url="https://download.pytorch.org/whl/cpu")
)
MAX_IMAGE_BYTES = 1_500_000


@app.cls(image=IMAGE, volumes={"/models": VOL}, secrets=[modal.Secret.from_name("beokay-ml-auth")], cpu=2, memory=2048, scaledown_window=120, timeout=60)
class DishClassifier:
    @modal.enter()
    def load(self):
        import torch
        from torchvision import models, transforms

        VOL.reload()
        current = json.load(open("/models/dish/current.json"))
        base = f"/models/dish/{current['version']}"
        raw = open(f"{base}/model.pt", "rb").read()
        digest = hashlib.sha256(raw).hexdigest()
        if digest != current["sha256"]:
            raise RuntimeError("SHA-256 artefak tidak cocok dengan current.json")  # menolak artefak yang berubah
        meta = json.load(open(f"{base}/classes.json"))
        self.version, self.sha, self.classes, self.temperature = current["version"], digest, meta["classes"], float(meta["temperature"])
        net = models.mobilenet_v3_large(weights=None)
        net.classifier[3] = torch.nn.Linear(net.classifier[3].in_features, len(self.classes))
        net.load_state_dict(torch.load(io.BytesIO(raw), map_location="cpu"))
        net.eval()
        self.net, self.torch = net, torch
        self.tf = transforms.Compose([transforms.Resize(256), transforms.CenterCrop(224), transforms.ToTensor(), transforms.Normalize(meta["mean"], meta["std"])])

    @modal.asgi_app()
    def web(self):
        from fastapi import FastAPI, Header, HTTPException
        from PIL import Image

        api = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

        @api.post("/")
        def predict(body: dict, authorization: str | None = Header(default=None)):
            token = os.environ.get("ML_AUTH_TOKEN", "")
            supplied = (authorization or "").removeprefix("Bearer ").strip()
            if not token or not hmac.compare_digest(supplied.encode(), token.encode()):
                raise HTTPException(status_code=401, detail="unauthorized")
            t0 = time.time()
            try:
                data = base64.b64decode(body["imageBase64"], validate=True)
                top_k = max(1, min(5, int(body.get("topK", 3))))
            except Exception:
                raise HTTPException(status_code=422, detail="invalid body")
            if len(data) == 0 or len(data) > MAX_IMAGE_BYTES:
                raise HTTPException(status_code=413, detail="image size")
            try:
                Image.open(io.BytesIO(data)).verify()
                im = Image.open(io.BytesIO(data)).convert("RGB")
            except Exception:
                raise HTTPException(status_code=422, detail="not an image")
            with self.torch.no_grad():
                probs = self.torch.softmax(self.net(self.tf(im).unsqueeze(0))[0] / self.temperature, 0)
            top = probs.topk(top_k)
            return {
                "modelKey": "dish-classifier",
                "modelVersion": self.version,
                "artifactSha256": self.sha,
                "predictions": [{"label": self.classes[i], "probability": round(float(p), 4)} for p, i in zip(top.values, top.indices)],
                "latencyMs": round((time.time() - t0) * 1000, 1),
            }

        return api
