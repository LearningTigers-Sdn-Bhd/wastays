# frozen_string_literal: true

module VendorDirectory
  OpeningHours = Data.define(:days, :opens, :closes) do
    def closed? = opens.to_s.casecmp?("closed")

    def label = closed? ? "Closed" : "#{opens} – #{closes}"
  end
end
