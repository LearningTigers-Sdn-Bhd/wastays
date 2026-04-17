class BaseGlobalSearchService
  include Rails.application.routes.url_helpers

  def initialize(query)
    @query = query.to_s.strip.downcase
  end

  # --- Scoring Logic ---

  def search_score(text, query)
    return 1 if query.blank?

    score = 0
    score += 120 if text.include?(query)

    query_tokens = tokenize(query)
    text_tokens = tokenize(text)
    return 0 if query_tokens.empty? || text_tokens.empty?

    query_tokens.each do |query_token|
      best_token_score = text_tokens.map { |text_token| token_similarity_score(query_token, text_token) }.max.to_i
      score += best_token_score
    end

    score
  end

  def tokenize(text)
    text.to_s.downcase.scan(/[a-z0-9]+/)
  end

  def token_similarity_score(query_token, text_token)
    return 35 if text_token == query_token
    return 30 if text_token.start_with?(query_token)
    return 26 if text_token.include?(query_token)
    return 18 if subsequence_match?(query_token, text_token)

    distance = levenshtein_distance(query_token, text_token)
    return 14 if distance == 1
    return 9 if distance == 2

    0
  end

  def subsequence_match?(needle, haystack)
    index = 0
    needle.each_char do |char|
      found_index = haystack.index(char, index)
      return false if found_index.nil?

      index = found_index + 1
    end
    true
  end

  def levenshtein_distance(a, b)
    a_len = a.length
    b_len = b.length
    return b_len if a_len.zero?
    return a_len if b_len.zero?

    prev = (0..b_len).to_a
    curr = Array.new(b_len + 1, 0)

    (1..a_len).each do |i|
      curr[0] = i
      (1..b_len).each do |j|
        cost = a[i - 1] == b[j - 1] ? 0 : 1
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost
        ].min
      end
      prev, curr = curr, prev
    end

    prev[b_len]
  end
end
