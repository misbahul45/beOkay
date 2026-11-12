export const FHIR_EXPORT_VERSION = "beokay-fhir-r4-v1";
export const LOINC = "http://loinc.org";
export const UCUM = "http://unitsofmeasure.org";
const CATEGORY = "http://terminology.hl7.org/CodeSystem/observation-category";

type Coding = { system: string; code: string; display: string };
type Mapping = { coding: Coding | null; text: string; ucum: string };

const loinc = (code: string, display: string): Coding => ({ system: LOINC, code, display });
const UCUM_CODES: Record<string, string> = { "mg/dL": "mg/dL", "mmol/L": "mmol/L", "%": "%", "mmol/mol": "mmol/mol", kg: "kg", cm: "cm", mmHg: "mm[Hg]", "mg/g": "mg/g", "umol/L": "umol/L", "mL/min/1.73m2": "mL/min/{1.73_m2}", "mg/mmol": "mg/mmol" };

const LAB_CODES: Record<string, Record<string, Coding>> = {
  hba1c: { "%": loinc("4548-4", "Hemoglobin A1c/Hemoglobin.total in Blood"), "mmol/mol": loinc("59261-8", "Hemoglobin A1c/Hemoglobin.total in Blood by IFCC protocol") },
  fasting_glucose: { "mg/dL": loinc("1558-6", "Fasting glucose [Mass/volume] in Serum or Plasma"), "mmol/L": loinc("14771-0", "Fasting glucose [Moles/volume] in Serum or Plasma") },
  ldl: { "mg/dL": loinc("2089-1", "Cholesterol in LDL [Mass/volume] in Serum or Plasma"), "mmol/L": loinc("22748-8", "Cholesterol in LDL [Moles/volume] in Serum or Plasma") },
  hdl: { "mg/dL": loinc("2085-9", "Cholesterol in HDL [Mass/volume] in Serum or Plasma"), "mmol/L": loinc("14646-4", "Cholesterol in HDL [Moles/volume] in Serum or Plasma") },
  total_cholesterol: { "mg/dL": loinc("2093-3", "Cholesterol [Mass/volume] in Serum or Plasma"), "mmol/L": loinc("14647-2", "Cholesterol [Moles/volume] in Serum or Plasma") },
  triglycerides: { "mg/dL": loinc("2571-8", "Triglyceride [Mass/volume] in Serum or Plasma"), "mmol/L": loinc("14927-8", "Triglyceride [Moles/volume] in Serum or Plasma") },
  creatinine: { "mg/dL": loinc("2160-0", "Creatinine [Mass/volume] in Serum or Plasma"), "umol/L": loinc("14682-9", "Creatinine [Moles/volume] in Serum or Plasma") },
  urine_acr: { "mg/g": loinc("9318-7", "Albumin/Creatinine [Mass Ratio] in Urine") },
};
const LAB_TEXT: Record<string, string> = { hba1c: "HbA1c", fasting_glucose: "Glukosa puasa (lab)", ldl: "Kolesterol LDL", hdl: "Kolesterol HDL", total_cholesterol: "Kolesterol total", triglycerides: "Trigliserida", creatinine: "Kreatinin", egfr: "eGFR", urine_acr: "Rasio albumin-kreatinin urin" };
const VITAL_CODES: Record<string, Coding | null> = { weight: loinc("29463-7", "Body weight"), height: loinc("8302-2", "Body height"), waist: null };
const VITAL_TEXT: Record<string, string> = { weight: "Berat badan", height: "Tinggi badan", waist: "Lingkar pinggang", blood_pressure: "Tekanan darah" };
const MEAL_CONTEXT: Record<string, string> = { fasting: "puasa", before_meal: "sebelum makan", after_meal: "setelah makan", bedtime: "sebelum tidur", other: "lainnya" };

export function labMapping(test: string, unit: string): Mapping {
  return { coding: LAB_CODES[test]?.[unit] ?? null, text: LAB_TEXT[test] ?? test, ucum: UCUM_CODES[unit] ?? unit };
}

const category = (code: "vital-signs" | "laboratory" | "activity") => [{ coding: [{ system: CATEGORY, code }] }];
const codeOf = (m: { coding: Coding | null; text: string }) => (m.coding ? { coding: [m.coding], text: m.text } : { text: m.text });
const quantity = (value: number, unit: string, ucum: string) => ({ value, unit, system: UCUM, code: ucum });
const round = (v: number, d = 2) => Math.round(v * 10 ** d) / 10 ** d;

export type FhirInput = {
  patientId: string;
  name: string | null;
  generatedAt: Date;
  glucose: { id: string; valueMgDl: number; measuredAt: Date; mealContext: string; source: string }[];
  labs: { id: string; test: string; value: number; unit: string; sampledAt: Date }[];
  vitals: { id: string; kind: string; value: number; value2: number | null; unit: string; measuredAt: Date }[];
  steps: { id: string; localDate: Date; steps: number }[];
};

export function buildFhirBundle(input: FhirInput) {
  const subject = { reference: `urn:uuid:${input.patientId}` };
  const patient = { resourceType: "Patient", id: input.patientId, ...(input.name ? { name: [{ text: input.name }] } : {}) };
  const obs = (id: string, cat: "vital-signs" | "laboratory" | "activity", code: object, effective: object, rest: object) => ({
    resourceType: "Observation",
    id,
    status: "final",
    category: category(cat),
    code,
    subject,
    ...effective,
    performer: [subject],
    ...rest,
  });
  const resources: object[] = [patient];
  for (const g of input.glucose) {
    const ctx = MEAL_CONTEXT[g.mealContext];
    resources.push(obs(g.id, "laboratory", { coding: [loinc("41653-7", "Glucose [Mass/volume] in Capillary blood by Glucometer")], text: "Glukosa darah kapiler" }, { effectiveDateTime: g.measuredAt.toISOString() }, { valueQuantity: quantity(round(g.valueMgDl, 1), "mg/dL", "mg/dL"), ...(ctx ? { note: [{ text: `Konteks: ${ctx}` }] } : {}), ...(g.source !== "manual_glucometer" ? { method: { text: g.source } } : {}) }));
  }
  for (const l of input.labs) {
    const m = labMapping(l.test, l.unit);
    resources.push(obs(l.id, "laboratory", codeOf(m), { effectiveDateTime: l.sampledAt.toISOString().slice(0, 10) }, { valueQuantity: quantity(l.value, l.unit, m.ucum) }));
  }
  for (const v of input.vitals) {
    if (v.kind === "blood_pressure") {
      resources.push(
        obs(v.id, "vital-signs", { coding: [loinc("85354-9", "Blood pressure panel with all children optional")], text: VITAL_TEXT.blood_pressure }, { effectiveDateTime: v.measuredAt.toISOString() }, {
          component: [
            { code: { coding: [loinc("8480-6", "Systolic blood pressure")] }, valueQuantity: quantity(v.value, "mmHg", "mm[Hg]") },
            ...(v.value2 !== null ? [{ code: { coding: [loinc("8462-4", "Diastolic blood pressure")] }, valueQuantity: quantity(v.value2, "mmHg", "mm[Hg]") }] : []),
          ],
        }),
      );
      continue;
    }
    const coding = VITAL_CODES[v.kind] ?? null;
    resources.push(obs(v.id, "vital-signs", codeOf({ coding, text: VITAL_TEXT[v.kind] ?? v.kind }), { effectiveDateTime: v.measuredAt.toISOString() }, { valueQuantity: quantity(v.value, v.unit, UCUM_CODES[v.unit] ?? v.unit) }));
  }
  for (const s of input.steps) {
    const day = s.localDate.toISOString().slice(0, 10);
    resources.push(obs(s.id, "activity", { coding: [loinc("41950-7", "Number of steps in 24 hour Measured")], text: "Langkah harian" }, { effectivePeriod: { start: day, end: day } }, { valueQuantity: quantity(s.steps, "langkah/hari", "/(24.h)") }));
  }
  return {
    resourceType: "Bundle",
    id: crypto.randomUUID(),
    meta: { lastUpdated: input.generatedAt.toISOString(), tag: [{ system: "https://beokay.app/fhir/export", code: FHIR_EXPORT_VERSION }] },
    type: "collection",
    timestamp: input.generatedAt.toISOString(),
    entry: resources.map((r) => ({ fullUrl: `urn:uuid:${(r as { id: string }).id}`, resource: r })),
  };
}
