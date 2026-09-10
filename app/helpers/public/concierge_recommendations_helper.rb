# frozen_string_literal: true

module Public::ConciergeRecommendationsHelper
  # One brand treatment, not a different colour per vendor: WAStays only has
  # two real accent hues (the deep teal primary and the warm gold accent), and
  # borrowing the rest of the Tailwind palette to tell vendors apart never
  # read as "on brand". Every vendor's photo wash, icon chip, badge and card
  # border now draws from the same tokens the rest of the concierge uses.
  WAYS_ACCENT = {
    wash: "from-primary to-primary-active",
    chip: "bg-primary/10 text-primary",
    badge: "bg-primary text-primary-foreground",
    border: "border-primary/25"
  }.freeze

  # This section nests three deep (tabs -> vendor -> voucher) and is used almost
  # entirely on a phone, where the OS and browser already provide back. The
  # in-page button is kept for pointer widths, where there is no such gesture.
  DESKTOP_ONLY_BACK_CLASS = "mb-6 hidden sm:flex sm:justify-end"

  def desktop_only_back_class = DESKTOP_ONLY_BACK_CLASS

  # vendor is unused now but kept in the signature -- every call site already
  # passes one, and a per-vendor treatment is one line to bring back here if
  # the brand ever grows a wider palette to draw it from.
  def vendor_accent(_vendor, part) = WAYS_ACCENT.fetch(part)

  def category_icon_for(slug)
    VendorDirectory.category(slug)&.icon || "store"
  end

  # Halal status is a stop/go decision for a lot of Malaysian guests, not
  # trivia -- it gets its own icon and its own colour rather than sitting in
  # the generic tags row where "Halal" and "Rooftop" would read as equally
  # important. Green is reassurance (Halal, a confirmed vegetarian menu);
  # "Non-Halal" is neutral information, not a warning, so it stays muted.
  DIETARY_TAG_ICONS = {
    "Halal" => "moon-star",
    "Non-Halal" => "info",
    "Pork-Free" => "ban",
    "Vegetarian Options" => "leaf"
  }.freeze

  DIETARY_TAG_CLASSES = {
    "Halal" => "bg-success/10 text-success",
    "Non-Halal" => "bg-muted text-muted-foreground",
    "Pork-Free" => "bg-success/10 text-success",
    "Vegetarian Options" => "bg-success/10 text-success"
  }.freeze

  # Text-only pairing for the one place (the card-mode photo badge) that
  # supplies its own white ground instead of using the tinted one above.
  DIETARY_TAG_TEXT_CLASSES = {
    "Halal" => "text-success",
    "Non-Halal" => "text-muted-foreground",
    "Pork-Free" => "text-success",
    "Vegetarian Options" => "text-success"
  }.freeze

  def dietary_tag_icon(label) = DIETARY_TAG_ICONS.fetch(label, "info")

  def dietary_tag_classes(label) = DIETARY_TAG_CLASSES.fetch(label, "bg-muted text-muted-foreground")

  def dietary_tag_text_class(label) = DIETARY_TAG_TEXT_CLASSES.fetch(label, "text-muted-foreground")

  def vendor_distance_summary(vendor)
    [ vendor.distance_label, ("#{vendor.walking_minutes} min walk" if vendor.walking_minutes.present?) ]
      .compact_blank.join(" · ")
  end

  def offer_expiry_label(offer)
    return if offer.expires_on.blank?

    "Valid until #{l(offer.expires_on, format: :long)}"
  end

  # A remaining-count badge tells a guest exactly how replaceable they are;
  # "Ending soon" creates the same urgency without putting a number on it.
  # Expiry takes priority over stock -- a guest can still claim a scarce
  # offer next week, but not one that has already lapsed.
  def offer_urgency_label(offer)
    return "Ending soon" if offer.expiring_soon?
    return "Going fast" if offer.scarce?

    nil
  end

  # Encodes the URL a vendor's staff will land on when they scan, not the bare
  # code -- any phone camera then works and no vendor app is needed.
  def voucher_qr_data_url(entry)
    ::Concierge::QrSvg.data_url("#{root_url.chomp('/')}/v/#{entry.code}")
  end
end
