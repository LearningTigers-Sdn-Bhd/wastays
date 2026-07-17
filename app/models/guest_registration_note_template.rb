# frozen_string_literal: true

class GuestRegistrationNoteTemplate < ApplicationRecord
  belongs_to :hotel

  validates :title, presence: true
  validates :content, presence: true
end
