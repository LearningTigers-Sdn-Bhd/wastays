# frozen_string_literal: true

module GuestUI
  # What a list says when it has nothing to show.
  #
  # It says why it is empty and what to do next. An empty list and a search
  # that found nothing are two different states, and a guest needs a
  # different next step for each: book a stay, or clear the filters.
  class EmptyState < GuestUI::BaseComponent
    renders_one :action

    def initialize(icon:, title:, description: nil, class: nil)
      @icon = icon
      @title = title
      @description = description
      @class = binding.local_variable_get(:class)
    end

    private

    attr_reader :icon, :title, :description

    def empty_class = tw_merge("guest-empty-state", @class)
  end
end
