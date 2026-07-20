export type CameraStatus = {
  id: 'kids_room';
  displayName: string;
  isAvailable: boolean;
  isStreaming: boolean;
  speakerVolume: number;
  lastUpdatedAt?: string;
};

export type CameraSession = {
  id: string;
  streamURL: string;
  expiresAt: string;
};

export type CameraPanTiltDirection = 'UP' | 'DOWN' | 'LEFT' | 'RIGHT';
