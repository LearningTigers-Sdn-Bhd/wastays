# frozen_string_literal: true

module PanelsUI
  # Accessible modal sheet built on the native <dialog> element.
  #
  # The component renders only the sheet surface. Open it with a native invoker:
  #
  #   <button command="show-modal" commandfor="filters">Filters</button>
  #
  # Close through `panels-ui--sheet#close` so the exit transition and overlay
  # stack complete before the native dialog leaves the top layer.
  class Sheet < PanelsUI::BaseComponent
    renders_one :header
    renders_one :body
    renders_one :footer

    SIDES = %i[right left top bottom].freeze
    SIZES = %i[sm md lg full].freeze
    VARIANTS = %i[edge floating].freeze

    BASE_CLASSES = "fixed m-0 hidden open:flex flex-col overflow-hidden " \
                   "bg-card text-card-foreground border border-border shadow-lg p-0 z-modal " \
                   "transform-gpu transition-transform duration-300 ease-out motion-reduce:transition-none " \
                   "backdrop:bg-black/50 backdrop:backdrop-blur-sm"

    POSITION_CLASSES = {
      edge: {
        right:  "inset-y-0 right-0 left-auto h-dvh max-h-none translate-x-full data-[panels-open]:translate-x-0 rounded-l-lg",
        left:   "inset-y-0 left-0 right-auto h-dvh max-h-none -translate-x-full data-[panels-open]:translate-x-0 rounded-r-lg",
        top:    "inset-x-0 top-0 bottom-auto w-dvw max-w-none -translate-y-full data-[panels-open]:translate-y-0 rounded-b-lg",
        bottom: "inset-x-0 bottom-0 top-auto w-dvw max-w-none translate-y-full data-[panels-open]:translate-y-0 rounded-t-lg"
      },
      floating: {
        right:  "top-4 bottom-4 right-4 left-auto h-[calc(100dvh-2rem)] max-h-none translate-x-[calc(100%+1rem)] data-[panels-open]:translate-x-0 rounded-lg",
        left:   "top-4 bottom-4 left-4 right-auto h-[calc(100dvh-2rem)] max-h-none -translate-x-[calc(100%+1rem)] data-[panels-open]:translate-x-0 rounded-lg",
        top:    "inset-x-4 top-4 bottom-auto w-[calc(100dvw-2rem)] max-w-none -translate-y-[calc(100%+1rem)] data-[panels-open]:translate-y-0 rounded-lg",
        bottom: "inset-x-4 bottom-4 top-auto w-[calc(100dvw-2rem)] max-w-none translate-y-[calc(100%+1rem)] data-[panels-open]:translate-y-0 rounded-lg"
      }
    }.freeze

    DIMENSION_CLASSES = {
      edge: {
        vertical: {
          sm:   "w-[20rem] max-w-[100dvw]",
          md:   "w-[28rem] max-w-[100dvw]",
          lg:   "w-[36rem] max-w-[100dvw]",
          full: "w-dvw max-w-none rounded-none"
        },
        horizontal: {
          sm:   "h-[20rem] max-h-[100dvh]",
          md:   "h-[28rem] max-h-[100dvh]",
          lg:   "h-[36rem] max-h-[100dvh]",
          full: "h-dvh max-h-none rounded-none"
        }
      },
      floating: {
        vertical: {
          sm:   "w-[20rem] max-w-[calc(100dvw-2rem)]",
          md:   "w-[28rem] max-w-[calc(100dvw-2rem)]",
          lg:   "w-[36rem] max-w-[calc(100dvw-2rem)]",
          full: "w-[calc(100dvw-2rem)] max-w-none"
        },
        horizontal: {
          sm:   "h-[20rem] max-h-[calc(100dvh-2rem)]",
          md:   "h-[28rem] max-h-[calc(100dvh-2rem)]",
          lg:   "h-[36rem] max-h-[calc(100dvh-2rem)]",
          full: "h-[calc(100dvh-2rem)] max-h-none"
        }
      }
    }.freeze

    def initialize(id:, side: :right, size: :md, variant: :edge, title: nil, aria_label: nil,
                   description: nil, dismissible: true, body_class: nil, class: nil)
      if title.blank? && aria_label.blank?
        raise ArgumentError, "Sheet requires a visible title or an aria_label"
      end

      @id = id
      @side = SIDES.include?(side) ? side : :right
      @size = SIZES.include?(size) ? size : :md
      @variant = VARIANTS.include?(variant) ? variant : :edge
      @title = title
      @aria_label = aria_label
      @description = description
      @dismissible = dismissible
      @body_class = body_class
      @class = binding.local_variable_get(:class)
    end

    def sheet_classes
      tw_merge([
        BASE_CLASSES,
        POSITION_CLASSES.fetch(@variant).fetch(@side),
        DIMENSION_CLASSES.fetch(@variant).fetch(axis).fetch(@size),
        @class
      ])
    end

    def title_id = "#{@id}-title"
    def desc_id = "#{@id}-desc"

    private

    def axis
      %i[right left].include?(@side) ? :vertical : :horizontal
    end
  end
end
