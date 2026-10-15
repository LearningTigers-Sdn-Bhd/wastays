# frozen_string_literal: true

module VendorDirectory
  Category = Data.define(:slug, :name, :tagline, :icon) do
    def to_param = slug
  end
end
