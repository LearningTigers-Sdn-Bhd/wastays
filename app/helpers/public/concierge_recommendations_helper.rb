# frozen_string_literal: true

module Public::ConciergeRecommendationsHelper
  # Tailwind scans source for literal class names, so every accent has to be
  # written out rather than interpolated. Each vendor picks one; it colours the
  # card header, the icon chip and the offer badge so a vendor stays visually
  # recognisable as a guest moves from the list into its detail page.
  #
  # `soft` is the pastel pairing used by the featured rail: a 100-weight ground
  # under 900-weight text, which clears AA comfortably at the small sizes those
  # cards use, where white-on-saturated did not.
  ACCENTS = {
    "amber" => {
      wash: "from-amber-500 to-amber-700",
      chip: "bg-amber-50 text-amber-700",
      badge: "bg-amber-600 text-white",
      soft: "border-amber-200 bg-amber-100 text-amber-900",
      border: "border-amber-300"
    },
    "rose" => {
      wash: "from-rose-500 to-rose-700",
      chip: "bg-rose-50 text-rose-700",
      badge: "bg-rose-600 text-white",
      soft: "border-rose-200 bg-rose-100 text-rose-900",
      border: "border-rose-300"
    },
    "orange" => {
      wash: "from-orange-500 to-orange-700",
      chip: "bg-orange-50 text-orange-700",
      badge: "bg-orange-600 text-white",
      soft: "border-orange-200 bg-orange-100 text-orange-900",
      border: "border-orange-300"
    },
    "emerald" => {
      wash: "from-emerald-500 to-emerald-700",
      chip: "bg-emerald-50 text-emerald-700",
      badge: "bg-emerald-600 text-white",
      soft: "border-emerald-200 bg-emerald-100 text-emerald-900",
      border: "border-emerald-300"
    },
    "violet" => {
      wash: "from-violet-500 to-violet-700",
      chip: "bg-violet-50 text-violet-700",
      badge: "bg-violet-600 text-white",
      soft: "border-violet-200 bg-violet-100 text-violet-900",
      border: "border-violet-300"
    },
    "teal" => {
      wash: "from-teal-500 to-teal-700",
      chip: "bg-teal-50 text-teal-700",
      badge: "bg-teal-600 text-white",
      soft: "border-teal-200 bg-teal-100 text-teal-900",
      border: "border-teal-300"
    },
    "green" => {
      wash: "from-green-500 to-green-700",
      chip: "bg-green-50 text-green-700",
      badge: "bg-green-600 text-white",
      soft: "border-green-200 bg-green-100 text-green-900",
      border: "border-green-300"
    },
    "lime" => {
      wash: "from-lime-500 to-lime-700",
      chip: "bg-lime-50 text-lime-700",
      badge: "bg-lime-600 text-white",
      soft: "border-lime-200 bg-lime-100 text-lime-900",
      border: "border-lime-300"
    },
    "sky" => {
      wash: "from-sky-500 to-sky-700",
      chip: "bg-sky-50 text-sky-700",
      badge: "bg-sky-600 text-white",
      soft: "border-sky-200 bg-sky-100 text-sky-900",
      border: "border-sky-300"
    },
    "cyan" => {
      wash: "from-cyan-500 to-cyan-700",
      chip: "bg-cyan-50 text-cyan-700",
      badge: "bg-cyan-600 text-white",
      soft: "border-cyan-200 bg-cyan-100 text-cyan-900",
      border: "border-cyan-300"
    },
    "fuchsia" => {
      wash: "from-fuchsia-500 to-fuchsia-700",
      chip: "bg-fuchsia-50 text-fuchsia-700",
      badge: "bg-fuchsia-600 text-white",
      soft: "border-fuchsia-200 bg-fuchsia-100 text-fuchsia-900",
      border: "border-fuchsia-300"
    },
    "indigo" => {
      wash: "from-indigo-500 to-indigo-700",
      chip: "bg-indigo-50 text-indigo-700",
      badge: "bg-indigo-600 text-white",
      soft: "border-indigo-200 bg-indigo-100 text-indigo-900",
      border: "border-indigo-300"
    }
  }.freeze

  DEFAULT_ACCENT = ACCENTS.fetch("emerald")

  # This section nests three deep (tabs -> vendor -> voucher) and is used almost
  # entirely on a phone, where the OS and browser already provide back. The
  # in-page button is kept for pointer widths, where there is no such gesture.
  DESKTOP_ONLY_BACK_CLASS = "mb-6 hidden sm:flex sm:justify-end"

  def desktop_only_back_class = DESKTOP_ONLY_BACK_CLASS

  def vendor_accent(vendor, part) = ACCENTS.fetch(vendor.accent, DEFAULT_ACCENT).fetch(part)

  def category_icon_for(slug)
    VendorDirectory.category(slug)&.icon || "store"
  end

  def vendor_distance_summary(vendor)
    [ vendor.distance_label, ("#{vendor.walking_minutes} min walk" if vendor.walking_minutes.present?) ]
      .compact_blank.join(" · ")
  end

  def offer_expiry_label(offer)
    return if offer.expires_on.blank?

    "Valid until #{l(offer.expires_on, format: :long)}"
  end

  # Encodes the URL a vendor's staff will land on when they scan, not the bare
  # code -- any phone camera then works and no vendor app is needed.
  def voucher_qr_data_url(entry)
    ::Concierge::QrSvg.data_url("#{root_url.chomp('/')}/v/#{entry.code}")
  end
end
