# frozen_string_literal: true

class HotelPrefixHistory < ApplicationRecord
  belongs_to :hotel

  validates :prefix, presence: true, uniqueness: true
end
