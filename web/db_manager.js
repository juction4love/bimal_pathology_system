// db_manager.js – Full IndexedDB manager with CRUD & store‑clear functions
// ---------------------------------------------------------------
// Stores: patients, samples, results
// ---------------------------------------------------------------

class IndexedDBManager {
  constructor(dbName = "BimalPathologyDB", version = 1) {
    this.dbName = dbName;
    this.version = version;
    this.db = null;
  }

  // १. डेटाबेस सुरु गर्ने र स्टोरहरू बनाउने
  init() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, this.version);

      request.onupgradeneeded = (event) => {
        const db = event.target.result;

        if (!db.objectStoreNames.contains("patients")) {
          const patientStore = db.createObjectStore("patients", { keyPath: "patientId" });
          patientStore.createIndex("by_name", "name", { unique: false });
        }
        if (!db.objectStoreNames.contains("samples")) {
          db.createObjectStore("samples", { keyPath: "sampleId" });
        }
        if (!db.objectStoreNames.contains("results")) {
          db.createObjectStore("results", { keyPath: "resultId" });
        }
      };

      request.onsuccess = (event) => {
        this.db = event.target.result;
        console.log("IndexedDB सफलतापूर्वक जोडियो!");
        resolve(this.db);
      };

      request.onerror = (event) => reject(event.target.error);
    });
  }

  // २. डाटा सेभ वा अपडेट गर्ने (Upsert)
  addData(storeName, data) {
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      const request = store.put(data);

      request.onsuccess = () => resolve(true);
      request.onerror = (e) => reject(e.target.error);
    });
  }

  // ३. ID को आधारमा डाटा तान्ने
  getDataById(storeName, id) {
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(storeName, "readonly");
      const store = transaction.objectStore(storeName);
      const request = store.get(id);

      request.onsuccess = () => resolve(request.result);
      request.onerror = (e) => reject(e.target.error);
    });
  }

  // ४. स्टोरको सबै डाटा तान्ने
  getAllData(storeName) {
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(storeName, "readonly");
      const store = transaction.objectStore(storeName);
      const request = store.getAll();

      request.onsuccess = () => resolve(request.result);
      request.onerror = (e) => reject(e.target.error);
    });
  }

  // ५. नयाँ थपिएको: ID को आधारमा डाटा डिलिट गर्ने (Delete)
  deleteData(storeName, id) {
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      const request = store.delete(id);

      request.onsuccess = () => {
        console.log(`${id} भएको डाटा ${storeName} बाट हटाइयो।`);
        resolve(true);
      };
      request.onerror = (e) => reject(e.target.error);
    });
  }

  // ६. नयाँ थपिएको: एउटा स्टोरको सबै डाटा सफा गर्ने (Clear)
  clearStore(storeName) {
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      const request = store.clear();

      request.onsuccess = () => {
        console.log(`${storeName} स्टोर पूर्ण रूपमा खाली गरियो।`);
        resolve(true);
      };
      request.onerror = (e) => reject(e.target.error);
    });
  }
}

export default IndexedDBManager;
export { IndexedDBManager };
