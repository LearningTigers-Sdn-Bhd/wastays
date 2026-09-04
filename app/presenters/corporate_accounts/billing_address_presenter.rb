# frozen_string_literal: true

module CorporateAccounts
  class BillingAddressPresenter
    delegate :complete?, :missing?, :incomplete?, :lines, :display, :snapshot, to: :@address

    def initialize(source)
      @address = PostalAddresses::Presenter.new(values_from(source))
    end

    def status_label
      return "Billing address missing" if missing?
      return "Billing address incomplete" if incomplete?

      "Billing address complete"
    end

    private

    def values_from(source)
      PostalAddresses::Presenter::FIELDS.index_with do |field|
        value = if source.respond_to?(:key?)
          source[field] || source[field.to_sym]
        else
          source.public_send("billing_#{field}")
        end
        value.to_s.strip.presence
      end
    end
  end
end
