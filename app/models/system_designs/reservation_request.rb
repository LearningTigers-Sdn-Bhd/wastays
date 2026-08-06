# frozen_string_literal: true

module SystemDesigns
  # Throwaway form object powering the form-submission preview. It is never
  # persisted — it exists so the showcase can demonstrate a real Turbo round-trip
  # with server-side validation, inline errors, and loading/result toasts.
  class ReservationRequest
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :guest_name, :string
    attribute :email, :string
    attribute :nights, :integer

    validates :guest_name, presence: true
    validates :email, presence: true,
                      format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email", allow_blank: true }
    validates :nights, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  end
end
