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

  # Same idea as an offer's own "Ending soon": open but about to close reads
  # as its own state, not a quieter version of "Open now" -- a guest walking
  # over needs to know the door is about to shut, not just that it currently
  # isn't. Checked before the plain open/closed cases so it wins whenever it
  # applies.
  def vendor_open_now_label(vendor)
    return if vendor.hours.empty?
    return "Closing soon at #{vendor.closes_at.strftime('%-l:%M %p')}" if vendor.closing_soon?

    vendor.open_now? ? "Open now" : "Closed now"
  end

  def vendor_open_now_class(vendor)
    return "text-warning" if vendor.closing_soon?

    vendor.open_now? ? "text-success" : "text-destructive"
  end

  # "Closed now" on its own leaves a guest guessing whether that means five
  # minutes or five hours -- this is the answer. Today/Tomorrow read faster
  # than a weekday name at a glance; anything further out gets the name,
  # since "in 4 days" is harder to act on than "Thursday".
  def vendor_next_open_label(vendor)
    return if vendor.open_now?

    next_open = vendor.next_open_at
    return if next_open.blank?

    today = Time.current.in_time_zone(VendorDirectory::ZONE).to_date
    day_word = case next_open.to_date
    when today then "today"
    when today + 1 then "tomorrow"
    else next_open.strftime("%A")
    end

    "Opens #{day_word} #{next_open.strftime('%-l:%M %p')}"
  end

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

  # "3 days ago" reads faster than a calendar date for something as casual as
  # a review, but a review from months back is more useful as an actual date
  # than as "4 months ago" -- so only recent ones get the relative form.
  def review_posted_label(review)
    posted_at = review.posted_at.to_date
    days_ago = (Time.current.in_time_zone(VendorDirectory::ZONE).to_date - posted_at).to_i

    case days_ago
    when ..0 then "Today"
    when 1 then "Yesterday"
    when 2..13 then "#{days_ago} days ago"
    when 14..27 then "#{days_ago / 7} weeks ago"
    else l(posted_at, format: :long)
    end
  end

  # Encodes the URL a vendor's staff will land on when they scan, not the bare
  # code -- any phone camera then works and no vendor app is needed.
  def voucher_qr_data_url(entry)
    ::Concierge::QrSvg.data_url("#{root_url.chomp('/')}/v/#{entry.code}")
  end
end
