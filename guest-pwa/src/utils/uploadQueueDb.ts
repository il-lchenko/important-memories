const DB_NAME = 'im_uploads'
const DB_VERSION = 1
const STORE = 'frames'

export interface PersistedQueueItem {
  id: string
  shortCode: string
  blob: Blob
  width: number
  height: number
  capturedAt: string
  attempts: number
  createdAt: number
}

let dbPromise: Promise<IDBDatabase> | null = null

function openDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise
  dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains(STORE)) {
        const store = db.createObjectStore(STORE, { keyPath: 'id' })
        store.createIndex('shortCode', 'shortCode', { unique: false })
      }
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => {
      dbPromise = null
      reject(req.error)
    }
  })
  return dbPromise
}

function tx<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return openDb().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const t = db.transaction(STORE, mode)
        const store = t.objectStore(STORE)
        const req = run(store)
        req.onsuccess = () => resolve(req.result)
        req.onerror = () => reject(req.error)
      }),
  )
}

export async function enqueue(item: PersistedQueueItem): Promise<void> {
  try {
    await tx('readwrite', (s) => s.put(item))
  } catch (e) {
    console.warn('idb enqueue failed', e)
  }
}

export async function listForShortCode(shortCode: string): Promise<PersistedQueueItem[]> {
  try {
    const db = await openDb()
    return await new Promise<PersistedQueueItem[]>((resolve, reject) => {
      const t = db.transaction(STORE, 'readonly')
      const idx = t.objectStore(STORE).index('shortCode')
      const req = idx.getAll(shortCode)
      req.onsuccess = () => resolve((req.result as PersistedQueueItem[]).sort((a, b) => a.createdAt - b.createdAt))
      req.onerror = () => reject(req.error)
    })
  } catch (e) {
    console.warn('idb list failed', e)
    return []
  }
}

export async function remove(id: string): Promise<void> {
  try {
    await tx('readwrite', (s) => s.delete(id))
  } catch (e) {
    console.warn('idb remove failed', e)
  }
}

export async function bumpAttempts(id: string): Promise<void> {
  try {
    const db = await openDb()
    await new Promise<void>((resolve, reject) => {
      const t = db.transaction(STORE, 'readwrite')
      const s = t.objectStore(STORE)
      const g = s.get(id)
      g.onsuccess = () => {
        const cur = g.result as PersistedQueueItem | undefined
        if (!cur) { resolve(); return }
        cur.attempts = (cur.attempts ?? 0) + 1
        const p = s.put(cur)
        p.onsuccess = () => resolve()
        p.onerror = () => reject(p.error)
      }
      g.onerror = () => reject(g.error)
    })
  } catch (e) {
    console.warn('idb bump failed', e)
  }
}
