export interface UserFormErrors {
  name?: string;
  email?: string;
}

export function validateUserForm(name: string, email: string): UserFormErrors {
  const errors: UserFormErrors = {};
  const trimmedName = name.trim();
  const trimmedEmail = email.trim();

  if (trimmedName.length === 0) {
    errors.name = 'Full name is required.';
  } else if (trimmedName.length > 255) {
    errors.name = 'Full name must be 255 characters or fewer.';
  }

  if (trimmedEmail.length === 0) {
    errors.email = 'Email address is required.';
  } else if (trimmedEmail.length > 255) {
    errors.email = 'Email address must be 255 characters or fewer.';
  } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) {
    errors.email = 'Enter a valid email address.';
  }

  return errors;
}

export function serverUserErrors(value: unknown): UserFormErrors {
  if (typeof value !== 'object' || value === null || !('response' in value)) {
    return {};
  }

  const response = value.response;
  if (typeof response !== 'object' || response === null || !('data' in response)) {
    return {};
  }

  const data = response.data;
  if (typeof data !== 'object' || data === null || !('errors' in data)) {
    return {};
  }

  const errors = data.errors;
  if (typeof errors !== 'object' || errors === null) {
    return {};
  }

  const firstError = (field: string): string | undefined => {
    const messages = (errors as Record<string, unknown>)[field];
    return Array.isArray(messages) && typeof messages[0] === 'string'
      ? messages[0]
      : undefined;
  };

  return {
    name: firstError('name'),
    email: firstError('email'),
  };
}

export function apiUserErrorMessage(value: unknown, fallback: string): string {
  if (typeof value !== 'object' || value === null || !('response' in value)) {
    return fallback;
  }

  const response = value.response;
  if (typeof response !== 'object' || response === null || !('data' in response)) {
    return fallback;
  }

  const data = response.data;
  if (typeof data === 'object' && data !== null && 'message' in data) {
    const message = data.message;
    if (typeof message === 'string' && message.trim() !== '') return message;
  }

  return fallback;
}
