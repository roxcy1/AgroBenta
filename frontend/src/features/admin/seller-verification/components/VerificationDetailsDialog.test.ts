import { describe, expect, it } from 'vitest';
import type { SellerVerification } from '../api/useSellerVerifications';
import {
  applicantDeclaredNoBackImage,
  governmentIdTypeLabel,
} from './verificationDetails';

describe('Government ID review details', () => {
  it('displays canonical ID values with their readable labels', () => {
    expect(governmentIdTypeLabel('philippine_national_id'))
      .toBe('Philippine National ID (PhilID / ePhilID)');
    expect(governmentIdTypeLabel('drivers_license')).toBe("Driver's License (LTO)");
    expect(governmentIdTypeLabel('others')).toBe('Others');
    expect(governmentIdTypeLabel(null)).toBe('—');
  });

  it('distinguishes an explicit no-back declaration from a legacy missing side', () => {
    const record = { has_no_back_image: true } as SellerVerification;
    const legacy = { has_no_back_image: null } as SellerVerification;

    expect(applicantDeclaredNoBackImage(record)).toBe(true);
    expect(applicantDeclaredNoBackImage(legacy)).toBe(false);
  });
});
