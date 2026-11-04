import Testing
@testable import TrrekPlatform

@Test func emptyCacheHasNoLevel() {
    #expect(BacklightLevelCache().level(at: 10) == nil)
}

@Test func cachedLevelIsFreshForItsLifetime() {
    var cache = BacklightLevelCache()
    cache.store(0.5, at: 100)
    #expect(cache.level(at: 100) == 0.5)
    #expect(cache.level(at: 100 + BacklightLevelCache.lifetime - 0.01) == 0.5)
    // After a pause the level is read again.
    #expect(cache.level(at: 100 + BacklightLevelCache.lifetime) == nil)
    // A clock that went backwards (another time base) does not trust the cache either.
    #expect(cache.level(at: 99) == nil)
}

@Test func storingRefreshesTheLifetime() {
    var cache = BacklightLevelCache()
    cache.store(0.5, at: 100)
    cache.store(0.5625, at: 101)
    #expect(cache.level(at: 102) == 0.5625)
}

@Test func invalidateDropsTheLevel() {
    var cache = BacklightLevelCache()
    cache.store(0.5, at: 100)
    cache.invalidate()
    #expect(cache.level(at: 100) == nil)
}

@Test func targetStepsAndClamps() {
    #expect(BacklightLevelCache.target(from: 0.5, direction: 1, fine: false) == 0.5625)
    #expect(BacklightLevelCache.target(from: 0.5, direction: -3, fine: false) == 0.4375)
    #expect(BacklightLevelCache.target(from: 0.5, direction: 1, fine: true) == 0.515625)
    #expect(BacklightLevelCache.target(from: 0.98, direction: 1, fine: false) == 1)
    #expect(BacklightLevelCache.target(from: 0.01, direction: -1, fine: false) == 0)
}
