/**
 * Monolithic module containing Logger, Cache, and EventBus.
 * TODO: Decompose into separate modules.
 */

export class Logger {
  private prefix: string;

  constructor(prefix: string = "APP") {
    this.prefix = prefix;
  }

  log(message: string): string {
    const entry = `[${this.prefix}] ${message}`;
    console.log(entry);
    return entry;
  }

  error(message: string): string {
    const entry = `[${this.prefix} ERROR] ${message}`;
    console.error(entry);
    return entry;
  }
}

export class Cache<T> {
  private store = new Map<string, T>();

  set(key: string, value: T): void {
    this.store.set(key, value);
  }

  get(key: string): T | undefined {
    return this.store.get(key);
  }

  delete(key: string): boolean {
    return this.store.delete(key);
  }

  has(key: string): boolean {
    return this.store.has(key);
  }

  clear(): void {
    this.store.clear();
  }

  get size(): number {
    return this.store.size;
  }
}

type EventHandler = (...args: unknown[]) => void;

export class EventBus {
  private handlers = new Map<string, Set<EventHandler>>();
  private logger: Logger;

  constructor(logger?: Logger) {
    this.logger = logger ?? new Logger("EventBus");
  }

  on(event: string, handler: EventHandler): void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Set());
    }
    this.handlers.get(event)!.add(handler);
  }

  off(event: string, handler: EventHandler): void {
    this.handlers.get(event)?.delete(handler);
  }

  emit(event: string, ...args: unknown[]): void {
    this.logger.log(`Event emitted: ${event}`);
    const handlers = this.handlers.get(event);
    if (handlers) {
      for (const handler of handlers) {
        handler(...args);
      }
    }
  }

  listenerCount(event: string): number {
    return this.handlers.get(event)?.size ?? 0;
  }
}
