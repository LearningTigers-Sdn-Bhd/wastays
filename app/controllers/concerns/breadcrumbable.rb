# frozen_string_literal: true

module Breadcrumbable
  extend ActiveSupport::Concern

  included do
    helper_method :breadcrumb_appends, :breadcrumb_override, :breadcrumbs_overridden?
  end

  def append_breadcrumb(label_or_part, path = nil, siblings: nil)
    breadcrumb_appends << normalize_breadcrumb_part(label_or_part, path, siblings: siblings)
  end

  def override_breadcrumbs(*parts)
    @_breadcrumb_override = parts.flatten.map { |part| normalize_breadcrumb_part(part) }
  end

  def breadcrumb_appends
    @_breadcrumb_appends ||= []
  end

  def breadcrumb_override
    @_breadcrumb_override
  end

  def breadcrumbs_overridden?
    defined?(@_breadcrumb_override)
  end

  private

  def normalize_breadcrumb_part(part, path = nil, siblings: nil)
    if part.is_a?(Hash)
      part.symbolize_keys
    else
      { label: part, path: path, siblings: siblings }
    end
  end
end
