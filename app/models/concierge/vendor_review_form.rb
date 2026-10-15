# frozen_string_literal: true

module Concierge
  # Validates a guest's review before Concierge::ReviewBook stores it. Not
  # backed by a table -- see ReviewBook for why -- so this is where the shape
  # a real Review record would enforce (name present, rating 1-5, a comment
  # short enough to actually read) lives instead.
  class VendorReviewForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :guest_name, :string
    attribute :rating, :integer
    attribute :comment, :string

    validates :guest_name, presence: true, length: { maximum: 60 }
    validates :rating, inclusion: { in: 1..5, message: "must be between 1 and 5 stars" }
    validates :comment, length: { maximum: 500 }
  end
end
