export const getApnsPrivateKey = (inlineKey: string | undefined): string | undefined => {
  const trimmedKey = inlineKey?.trim();

  if (!trimmedKey) {
    return undefined;
  }

  const unquotedKey =
    (trimmedKey.startsWith('"') && trimmedKey.endsWith('"')) ||
    (trimmedKey.startsWith("'") && trimmedKey.endsWith("'"))
      ? trimmedKey.slice(1, -1)
      : trimmedKey;
  const privateKey = unquotedKey.replace(/\\n/g, '\n');

  if (
    !privateKey.includes('-----BEGIN PRIVATE KEY-----') ||
    !privateKey.includes('-----END PRIVATE KEY-----')
  ) {
    throw new Error('APNS_PRIVATE_KEY is not a valid .p8 private key value.');
  }

  return privateKey;
};
