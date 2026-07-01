export type LevyHomeUser = {
  id: number;
  firstName: string;
  lastName: string;
  email: string;
  mobileDevice?: string;
  lastLogin?: string;
};

export type UsersResponse = {
  ok: true;
  users: LevyHomeUser[];
  generatedAt: string;
};
