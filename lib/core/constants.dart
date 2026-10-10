const kAppName = 'Momir IRL';
const kScryfallUserAgent =
    'MomirIRL/1.0 (Flutter; https://github.com/Shimmmi/Momir)';
const kBulkDataUrl = 'https://api.scryfall.com/bulk-data';
const kOracleCardsUrl = 'https://api.scryfall.com/bulk-data/oracle-cards';
const kPrefsPrinterId = 'printer_remote_id';
const kPrefsPrinterName = 'printer_name';
const kPrefsPrinterKind = 'printer_link_kind';
const kPrefsReroll = 'reroll_enabled';
const kPrefsColorFilter = 'color_filter';
const kPrefsLastSyncIso = 'last_sync_iso';
const kMetaLastSync = 'last_sync_iso';
const kMetaCreatureCount = 'creature_count';
const kMetaSyncModes = 'sync_modes';
const kArtWidth = 384;

/// Real Magic card is 63.5 × 88.9 mm. On a 57 mm roll the whole receipt
/// (art and text) scales to 57 × 88.9 / 63.5 ≈ 79.8 mm, 638 dots at 203 dpi.
const kPrintCardHeight = 638;

/// Art window is about 39.9 mm of the 88.9 mm card, so the rules text still fits.
const kArtHeight = 286;
const kArtJpegQuality = 60;
const kDisplayMaxWidth = 750;
const kDisplayJpegQuality = 80;
const kArtConcurrency = 3;
const kScryfallDelay = Duration(milliseconds: 80);
const kMaxOracleHeight = 360.0;
const kMaxExactCmc = 15;
const kRasterBandHeight = 256;
const kPrintChunkBytes = 128;
const kPrintChunkPause = Duration(milliseconds: 2);
const kFeedLines = 18;
