# Generated PDFs

Rules 01–11 govern portal screens only. Generated PDFs follow this file instead.
Nothing here licenses screen-side exceptions.

**Print uses its own faces, deliberately.** Screens use Inter. PDFs use
**Public Sans** for text and **Bricolage Grotesque** for report titles. Public
Sans was designed for dense administrative print and holds up at the 7–8pt sizes
report metadata needs; Bricolage separates the report title from the hotel name
by typeface rather than by size alone. This divergence from Inter is a decision,
not drift. Do not "correct" PDFs back to Inter.

These faces, Noto Sans SC, and Noto Sans Symbols 2 are vendored in `app/assets/fonts`
with their OFL licences. Do not switch them to system fonts: a system font that lacks a bold sibling silently
renders every bold weight as regular, which is what these files exist to prevent.
Chinese text falls through to bundled static Noto Sans SC regular and bold
fonts, followed by Noto Sans Symbols 2 for checkboxes and other symbols.
Explicit Unicode-font environment overrides retain precedence. A missing
fallback is logged rather than fatal.

Use `PdfTheme` tokens. Never a raw number:

- `TYPE`: `display` 20 (title, display face), `stat` 14 (stat strip values),
  `subhead` 12 (hotel name), `heading` 11 (section titles), `body` 9 (table cells),
  `small` 8 (table headers, address), `micro` 7 (metadata and stat labels, footer)
- `SPACE`: 4pt grid — `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 20
- `COLORS`, `RULE_WIDTH`, `PAGE_MARGIN`, `TABLE_CELL_PADDING`,
  `LABEL_TRACKING`
- `format_date` / `format_time` for every date and time

Unlike screen UI, uppercase and tracking are correct for print at `micro`: they
carry the metadata label tier, which cannot rely on size alone at 7pt. Prawn
cannot reach OpenType small caps.

Rules that exist because breaking them has already caused bugs:

- **Never `shrink_to_fit` scale-critical text.** It makes the same role render at
  different sizes on different reports. Let text wrap instead.
- **Dense tables step *down* the scale, never up.** Report services pass column
  widths tuned to their current size; widening text silently overflows and
  *drops content*. Horizontal cell padding stays at 6 for the same reason.
- **Prawn cannot apply OpenType features at render time.** Public Sans has
  `tnum` frozen into the vendored files so money columns align. Any feature you
  need must be baked in at vendor time, not requested in code.
- **prawn-table measures row heights when the table is built.** A size set via
  `row(n).style` afterwards is drawn but not measured, so the row gets sized for
  the document default. Set sizes at cell construction.
- **prawn-table applies `cell_style` after per-cell hashes.** A per-cell colour
  that `cell_style` also sets will be overridden. `PdfDataTable` therefore keeps
  only padding and `valign` in `cell_style`; size, borders and colour are set on
  every cell at construction, which is also what lets a caller hand one cell its
  own hash.
- **prawn-table cells reject `character_spacing`.** Tracked text must be drawn
  with measured text boxes.
- **`pdf.font(family) { … }` returns the font, not the block.** A measurement
  taken inside one has to be carried out in a local, or the caller gets a
  `Prawn::Fonts::TTF` where it expected a height.

A table that carries more columns than its page holds takes `density: :dense`
(`TABLE_TYPE`), which steps the whole table down one size. It does not tighten
its columns or shrink one cell — a table has two sizes and no others. A block
narrower than the measure takes `position: :right`, and its section title goes
with it.

Summary metrics are `PdfStatStrip` — label above value, columns divided by hairlines,
never filled. A tint behind short values reads as an empty table header, which is why
the metadata strip dropped its own fill. The strip fits its column count to the page
(four across needs landscape, portrait takes three) because the value size is fixed by
its role and must not shrink to fit. Reach for it through
`PdfReportBuilder#add_summary`, or directly in a document that draws its own body.

Facts about the document sit in one of three places, and never in two at once:

- `PdfReportFrame`'s **metadata strip** — one short value per label, on one line,
  bounded by rules. The default is period, generated, prepared by.
- `PdfDetailGrid` — the same label-above-value tier without the bounding rules,
  wrapping to as many rows as the pairs need. For a second band of facts under
  the one the frame already drew.
- `PdfPartyBlocks` — headed columns, separated by white space rather than rules,
  every entry a label above its value. This is for the parties to a document: who
  it bills, who issued it, what it covers. A block holds a name and an address, so
  its columns end at different heights and a label-value *grid* cannot carry it.
  A document wearing party blocks passes `metadata: []` so the frame draws no
  strip above them. Labels never sit *beside* their values here: the columns are a
  third of a portrait page, so the longer values wrap mid-value while the shorter
  ones do not, and one stacked entry among inline ones reads as a mistake. A block
  may use one `{ columns: [...] }` entry to place two short, closely related facts
  on the same row; each fact still keeps its label above its value.

`PdfNoticeBand` carries a status that has to arrive before the document's numbers
do — a void, a reconstruction. `:danger` and `:warning` variants.

`PdfBadge` is the inline form: a pill of one or two words, set beside
something else rather than across the measure, for a question the reader has
already asked. It measures before it draws, so a caller can set a title against it
and know what is left of the line. `:positive`, `:warning`, `:danger` and
`:neutral` are tinted and say something about the document's state. `:outline` is
bordered rather than filled and says something about the sheet itself — which copy
of it you are holding. Two tinted badges side by side read as one claim in two
halves; one tinted and one outlined read as two facts of different kinds.

`PdfReportFrame` has two slots for them. `badge:` sets the title row between its
two ends — title left, badges right — and takes a string, a `{ label:, variant: }`
hash, or an array of either, laid out from the right margin inwards so a document
adding a second badge leaves the first where every other document puts it. That
row is for facts about the *document*: paid, void, overdue.

`masthead_badge:` sits higher, opposite the hotel identity and above the report
title, for a fact about the *sheet of paper* — which copy of it you are holding.
Whoever is filing it should not have to read as far as the title to sort it. It
defaults to `:outline` and reserves its own width, so a long hotel name wraps
rather than running under it.

`PdfSignatureBlock` is where a document is signed: clear air to sign into, a
hairline rule to sign above, and the label tracked beneath it, in one to three
columns. It takes an optional `image:` for a signature already captured and a
`caption:` for who signed and when. **It is not a bordered box** — the invoice
drew one and it read as another data table, because a box puts a second
horizontal beside the one you actually sign on. The border vocabulary here is
one hairline; a signing area does not get a second, and nothing in print is
dashed.

Build reports with `PdfReportBuilder`, which owns the frame, tables, and page
furniture. Reach for `PdfReportFrame` directly only when a document draws its own
body, and call `stamp_page_furniture` once at the end so continuation pages get a
running head. A document whose title is an identifier passes `eyebrow:` to name
what it is; a document that is not period-based passes its own `metadata:` pairs.
The footer marks every document `Confidential` because most are internal; a
document that goes to the guest or the payer passes `confidential: false`. Every
masthead names the ways of reaching the hotel, built by the frame from the hotel
it is given rather than passed in per document, so the line cannot say one thing
on an invoice and another on a voucher. A hotel that publishes none of them gets
no line at all rather than a row of dashes. A document whose masthead is a
snapshot hands the frame a hotel carrying live contact details: the identity is as
it was when the document was issued, but a number the hotel stopped answering
serves nobody.

Dense operational reports can pass `frame_variant: :compact` to
`PdfReportBuilder`. The compact frame keeps the hotel identity, report title, and
default metadata, but places the title and metadata in one measured row. It also
combines the hotel address and contact details into one wrapping line. The
standard frame remains the default. Use the compact frame only when the report
body benefits from more printable rows. Transactional documents keep the standard
frame.
