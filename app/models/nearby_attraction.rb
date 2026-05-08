# frozen_string_literal: true

class NearbyAttraction < ApplicationRecord
  belongs_to :hotel

  validates :name, :city, :country, presence: true
end
