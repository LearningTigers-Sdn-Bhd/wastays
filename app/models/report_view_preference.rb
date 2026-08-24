# frozen_string_literal: true

class ReportViewPreference < ApplicationRecord
  include HotelScopable

  belongs_to :user

  validates :report_key, presence: true, uniqueness: { scope: %i[hotel_id user_id] }
  validates :visible_columns, presence: true
end
