const required = (name) => {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable ${name}. Test credentials must be supplied by the operator and are never stored in the repository.`);
  }
  return value;
};

export const getAdminCredential = () => ({
  email: required('LIS_TEST_ADMIN_EMAIL'),
  password: required('LIS_TEST_ADMIN_PASSWORD'),
});

export const getTechCredential = () => ({
  email: required('LIS_TEST_TECH_EMAIL'),
  password: required('LIS_TEST_TECH_PASSWORD'),
});

export const getPasswordRotationInputs = () => ({
  admin: {
    ...getAdminCredential(),
    newPassword: required('LIS_TEST_ADMIN_NEW_PASSWORD'),
  },
  tech: {
    ...getTechCredential(),
    newPassword: required('LIS_TEST_TECH_NEW_PASSWORD'),
  },
});
