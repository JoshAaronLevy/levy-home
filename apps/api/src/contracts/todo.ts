import type { EventPushStatus } from './activity.js';

export type ToDoStatus = 'open' | 'completed' | 'canceled';
export type ToDoRecurring = 'daily' | 'weekly' | 'monthly' | 'quarterly';
export type ToDoItemAlert = unknown;
export type ToDoItemSubtask = unknown;

export const TODO_FAMILY_USER_IDS = [1, 2] as const;

export type ToDoCategory = {
  id: number;
  name?: string;
  updatedAt?: string;
};

export type ToDoItem = {
  id: number;
  name: string;
  status: ToDoStatus;
  locationIds: number[];
  locationDisplayText: string;
  date?: string;
  recurring?: ToDoRecurring;
  notes?: string;
  alerts: ToDoItemAlert[];
  subtasks: ToDoItemSubtask[];
  createdBy?: number;
  createdFor: number[];
  createdDate?: string;
};

export type ToDoListData = {
  items: ToDoItem[];
  categories: ToDoCategory[];
  locations: ToDoLocation[];
};

export type ToDoListResponse = {
  ok: true;
  items: ToDoItem[];
  categories: ToDoCategory[];
  locations: ToDoLocation[];
  generatedAt: string;
};

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

export type CreateToDoItemRequest = {
  name: string;
  status?: ToDoStatus;
  locationIds?: number[];
  date?: string | null;
  recurring?: ToDoRecurring | null;
  notes?: string | null;
  alerts?: ToDoItemAlert[] | null;
  subtasks?: ToDoItemSubtask[] | null;
  createdBy?: number | null;
  createdFor?: number[];
  actor?: string;
  mutationId?: string;
};

export type UpdateToDoItemRequest = {
  name?: string;
  status?: ToDoStatus;
  locationIds?: number[];
  date?: string | null;
  recurring?: ToDoRecurring | null;
  notes?: string | null;
  alerts?: ToDoItemAlert[] | null;
  subtasks?: ToDoItemSubtask[] | null;
  createdBy?: number | null;
  actor?: string;
  mutationId?: string;
};

export type DeleteToDoItemRequest = {
  actor?: string;
  mutationId?: string;
};

export type ToDoListMutationResponse = {
  ok: true;
  item: ToDoItem;
  mutationId: string;
  generatedAt: string;
  push?: EventPushStatus;
};

export type DeleteToDoItemResponse = {
  ok: true;
  itemId: number;
  item: ToDoItem;
  mutationId: string;
  generatedAt: string;
  push?: EventPushStatus;
};
