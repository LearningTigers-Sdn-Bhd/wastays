FactoryBot.define do
  factory :check_out_request do
    association :booking
    status { "pending" }
    requested_at { Time.current }
    metadata { {} }

    # A completed checkout records when it finished, the way the only thing that
    # completes one does. Without it the record could not be placed in the date
    # window the board reads its completed column through.
    after(:build) do |request|
      request.completed_at ||= Time.current if request.status == "completed"
    end
  end
end
