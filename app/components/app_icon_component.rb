# frozen_string_literal: true

# ViewComponent replacement for ApplicationHelper#cached_icon.
#
# Not wired into any views yet — this is groundwork for an incremental migration.
# Existing call sites keep calling `cached_icon` (or the `app_icon` helper alias
# below) until they're moved over one by one.
#
# The rendered SVG only depends on (name, library, from, variant, attributes), never
# on the current request or user, so unlike `cached_icon`'s per-request ivar cache,
# this memoizes markup for the lifetime of the process — the same icon is parsed by
# rails_icons at most once per boot, regardless of how many requests render it.
class AppIconComponent < ViewComponent::Base
  CACHE = Concurrent::Map.new

  def initialize(name, library: RailsIcons.configuration.default_library, from: nil, variant: nil, **attributes)
    @name = name
    @library = library
    @from = from || library
    @variant = variant
    @attributes = attributes
  end

  def call
    CACHE.fetch_or_store(cache_key) { render_icon }.dup.html_safe
  end

  private

  def cache_key
    [ @name.to_s, @library.to_s, @from.to_s, @variant&.to_s, @attributes ]
  end

  def render_icon
    helpers.icon(@name, library: @library, from: @from, variant: @variant, **@attributes).to_s.freeze
  rescue StandardError => e
    Rails.logger.error("Icon not found: #{@name} (#{e.message})")
    "".freeze
  end
end
