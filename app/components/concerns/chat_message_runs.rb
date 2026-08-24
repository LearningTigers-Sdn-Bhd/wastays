# frozen_string_literal: true

# Grouping consecutive messages from one author into a run.
#
# Shared by the two chat logs -- the guest's page and the staff inbox -- because
# they must agree on what a run is. They are drawn in different languages, but
# "did the same person say this next thing" is one question with one answer, and
# two copies of it drift the first time one side gains a sender role the other
# has not heard of.
#
# Lives beside TailwindVariants rather than in either library: PublicUI must not
# reach into PanelsUI for it, nor the reverse.
module ChatMessageRuns
  extend ActiveSupport::Concern

  private

  # Each message paired with where it sits in its run. A run of one is both the
  # first and the last, which is what a message rendered on its own -- a live
  # append, a preview -- should look like.
  def message_runs(messages)
    messages.each_with_index.map do |message, index|
      previous = messages[index - 1] if index.positive?

      [ message, {
        first_in_run: !same_author?(message, previous),
        last_in_run: !same_author?(message, messages[index + 1])
      } ]
    end
  end

  def same_author?(message, other)
    return false if other.nil?

    author_key(message) == author_key(other)
  end

  # Two staff replying in turn are two runs, not one. A system line always
  # stands alone, so it is never anyone's neighbour.
  def author_key(message)
    return [ :system, message.object_id ] if message.sender_role == "system"

    [ message.sender_role, message.sender_user_id ]
  end
end
