import Testing
@testable import Twinskaraoke

@Suite("Search genre presentation")
struct SearchGenrePaletteTests {
    @Test("Fallback palette selection is deterministic and normalized")
    func deterministicPaletteIndex() {
        #expect(SearchGenrePalette.index(for: "Future Funk", paletteCount: 12) == 0)
        #expect(SearchGenrePalette.index(for: "  FUTURE FUNK\n", paletteCount: 12) == 0)
        #expect(SearchGenrePalette.index(for: "Unknown Genre", paletteCount: 12) == 2)
        #expect(
            SearchGenrePalette.index(for: "Café", paletteCount: 12)
                == SearchGenrePalette.index(for: "Cafe\u{301}", paletteCount: 12)
        )
    }

    @Test("Fallback palette selection rejects an empty palette")
    func emptyPaletteHasNoIndex() {
        #expect(SearchGenrePalette.index(for: "Future Funk", paletteCount: 0) == nil)
    }
}
