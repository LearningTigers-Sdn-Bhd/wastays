# frozen_string_literal: true

module GuestUI
  # Short facts as label and value pairs: a check-in time, a parking price, a
  # Wi-Fi password. Two a row by default, so a pair of related facts reads side
  # by side; one a row for a narrow column.
  #
  # A fact with no value does not show, and a list with no facts draws
  # nothing. A half-filled section never prints an empty label.
  #
  # copy: marks a value the guest types somewhere else, such as a Wi-Fi
  # password. It is set in a monospace face and can be selected in one tap.
  #
  # icon: sits before the label. It is decorative; the label is the name.
  class FactList < GuestUI::BaseComponent
    Fact = Data.define(:label, :value, :copy, :icon)
    COLUMNS = [ 1, 2 ].freeze

    def initialize(facts:, columns: 2, class: nil, **attributes)
      @facts = facts.map { |fact| fact.is_a?(Fact) ? fact : Fact.new(label: fact[0], value: fact[1], copy: false, icon: nil) }
                    .select { |fact| fact.value.present? }
      @columns = COLUMNS.include?(columns) ? columns : 2
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def self.fact(label, value, copy: false, icon: nil) = Fact.new(label:, value:, copy:, icon:)

    def render? = @facts.any?

    def call
      tag.dl(**@attributes, class: tw_merge("guest-fact-list", @class), data: { columns: @columns }) do
        safe_join(@facts.map { |fact| fact_tag(fact) })
      end
    end

    private

    def fact_tag(fact)
      tag.div(class: ("guest-fact-list__fact--icon" if fact.icon)) do
        safe_join([
          (helpers.app_icon(fact.icon, class: "guest-fact-list__icon", aria: { hidden: "true" }) if fact.icon),
          tag.div do
            safe_join([
              tag.dt(fact.label, class: "guest-fact-list__label"),
              tag.dd(fact.value, class: "guest-fact-list__value", data: { copy: (true if fact.copy) })
            ])
          end
        ].compact)
      end
    end
  end
end
