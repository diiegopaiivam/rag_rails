class Chunker
  SIZE    = 3000 # ~750 tokens
  OVERLAP = 400

  def self.call(pages)
    chunks = []
    pages.each do |pg|
      text = pg[:text]
      next if text.blank?

      start = 0
      while start < text.length
        stop = [start + SIZE, text.length].min
        if stop < text.length
          cut = text.rindex(/\n\n|\. /, stop)
          stop = cut + 1 if cut && cut > start + SIZE / 2
        end
        piece = text[start...stop].strip
        chunks << { page: pg[:page], content: piece } if piece.length > 20
        break if stop >= text.length
        start = stop - OVERLAP
      end
    end
    chunks.each_with_index.map { |c, i| c.merge(position: i) }
  end
end
