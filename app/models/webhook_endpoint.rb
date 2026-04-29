# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  validates :name, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end
end
