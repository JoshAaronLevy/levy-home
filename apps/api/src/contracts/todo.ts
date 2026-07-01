export type ToDoLocation = {
  id: number;
  name: string;
  address?: string;
  mapkitTitle?: string;
  mapkitSubtitle?: string;
  latitude?: number;
  longitude?: number;
  createdBy?: number;
  createdDate: string;
  lastUsedDate?: string;
  useCount: number;
  isActive: boolean;
  favoritedBy: number[];
};

export type ToDoLocationsResponse = {
  ok: true;
  locations: ToDoLocation[];
  generatedAt: string;
};

export type CreateToDoLocationRequest = {
  name: string;
  address?: string | null;
  mapkitTitle?: string | null;
  mapkitSubtitle?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  createdBy?: number | null;
  favoritedBy?: number[];
};

export type ToDoLocationMutationResponse = {
  ok: true;
  location: ToDoLocation;
  generatedAt: string;
};
