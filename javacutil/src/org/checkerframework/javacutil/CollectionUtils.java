package org.checkerframework.javacutil;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Utility methods related to Java Collections
 */
public class CollectionUtils {

    /**
     * A Utility method for creating LRU cache
     * @param size  size of the cache
     * @return  a new cache with the provided size
     */
    public static <K, V> Map<K, V> createLRUCache(final int size) {
        return new LinkedHashMap<K, V>() {

            private static final long serialVersionUID = 5261489276168775084L;
            @Override
            protected boolean removeEldestEntry(Map.Entry<K, V> entry) {
                return size() > size;
            }
        };
    }

    /**
     * A Utility method for creating least recently used caches.
     *
     * @param initialCapacity initial size of the cache
     * @param maxSize max size of the cache before the LRU entry is dropped
     * @param loadFactor how full the cache can be before it is re-hashed
     * @param <K> type of the keys into the cache
     * @param <V> type of the objects being cached
     * @return LRU Cache
     */
    public static <K, V> Map<K, V> createLRUCache(final int initialCapacity, final int maxSize, final float loadFactor) {

        return new LinkedHashMap<K, V>(initialCapacity, loadFactor, true) {
            private static final long serialVersionUID = 3020243257407556390L;
            @Override
            protected boolean removeEldestEntry(Map.Entry<K, V> entry) {
                return size() > maxSize;
            }
        };
    }
}
