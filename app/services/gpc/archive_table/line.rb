module Gpc
  module ArchiveTable
    # One line of an archived evidence table, split into its three columns. `index` is the
    # line's position in the table, which is how rows know what is near what.
    Line = Struct.new(:index, :marker, :text, :grading, :garbled, keyword_init: true) do
      def empty?
        text.nil? && marker.nil? && grading.nil?
      end
    end
  end
end
