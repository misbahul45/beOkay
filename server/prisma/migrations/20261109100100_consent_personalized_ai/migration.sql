-- Tujuan consent opsional baru: personalized_ai (saran personal). Ditambahkan tanpa menaikkan versi kebijakan,
-- sehingga persetujuan yang sudah ada tetap berlaku; pengguna memberi tujuan ini secara eksplisit.
ALTER TABLE "consent_records" DROP CONSTRAINT "consent_records_purpose_valid";
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_purpose_valid"
  CHECK ("purpose" IN ('health_data_processing', 'descriptive_summaries', 'product_analytics', 'personalized_ai'));
