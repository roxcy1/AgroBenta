import type { SellerVerification } from '../api/useSellerVerifications';

const governmentIdLabels: Record<string, string> = {
  philippine_national_id: 'Philippine National ID (PhilID / ePhilID)',
  drivers_license: "Driver's License (LTO)",
  philhealth_id: 'PhilHealth ID',
  voters_id: "Voter's ID",
  postal_id: 'Postal ID',
  others: 'Others',
};

export function governmentIdTypeLabel(value: string | null): string {
  if (!value) return '—';
  return governmentIdLabels[value] ?? value;
}

export function applicantDeclaredNoBackImage(verification: SellerVerification): boolean {
  return verification.has_no_back_image === true;
}
