#
#--
# Copyright (c) 2009, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#++
#

#
# "made in Japan"
#
# jmettraux@gmail.com
#

require 'rufus/tokyo/cabinet/lib'
require 'rufus/tokyo/cabinet/util'


module Rufus::Tokyo

  #
  # A 'table' a table database.
  #
  #   http://alpha.mixi.co.jp/blog/?p=290
  #   http://tokyocabinet.sourceforge.net/spex-en.html#tctdbapi
  #
  # TODO : rdoc me !
  #
  class Table
    include CabinetLibMixin
    include TokyoContainerMixin

    def initialize (*args)

      path = args.first # car
      params = args[1..-1] # cdr

      mode = compute_open_mode(params)

      @db = self.lib.tctdbnew

      (lib.tctdbopen(@db, path, compute_open_mode(params)) == 1 ) || raise_error
    end

    #
    # Closes the table (and frees the datastructure allocated for it),
    # returns true in case of success.
    #
    def close
      result = lib.tctdbclose(@db)
      lib.tctdbdel(@db)
      (result == 1)
    end

    #
    # Generates a unique id (in the context of this Table instance)
    #
    def generate_unique_id
      lib.tctdbgenuid(@db)
    end
    alias :genuid :generate_unique_id

    #
    # Accepts a variable number of arguments, at least two. First one
    # is the primary key of the record, the others are the columns.
    #
    # One can also directly write
    #
    #   table['one'] = [ 'name', 'toto', 'age', '33' ]
    #   table['two'] = [ 'name', 'fred', 'age', '45' ]
    #
    # instead of
    #
    #   table.tabbed_put('one', 'name', 'toto', 'age', '33')
    #   table.tabbed_put('two', 'name', 'fred', 'age', '45')
    #
    # beware : inserting an array uses a tab separator...
    #
    def tabbed_put (pk, *args)

      cols = args.collect { |e| e.to_s }.join("\t")

      (lib.tctdbput3(@db, pk, cols) == 1) || raise_error

      args
    end

    #
    # Inserts a record in the table db
    #
    #   table['pk0'] = [ 'name', 'fred', 'age', '45' ]
    #   table['pk1'] = { 'name' => 'jeff', 'age' => '46' }
    #
    def []= (pk, h_or_a)

      return tabbed_put(pk, *h_or_a) if h_or_a.is_a?(Array)

      pklen = lib.strlen(pk)

      m = Rufus::Tokyo::Map.from_h(h_or_a)

      r = lib.tctdbput(@db, pk, pklen, m.pointer)

      m.free

      (r == 1) || raise_error

      h_or_a
    end

    #
    # Removes an entry in the table
    #
    # (might raise an error if the delete itself failed, but returns nil
    # if there was no entry for the given key)
    #
    def delete (k)
      v = self[k]
      return nil unless v
      (lib.tctdbout2(@db, k) == 1) || raise_error
      v
    end

    #
    # Removes all records in this table database
    #
    def clear
      (lib.tctdbvanish(@db) == 1) || raise_error
    end

    #
    # Returns the value (as a Ruby Hash) else nil
    #
    def [] (k)
      m = lib.tctdbget(@db, k, lib.strlen(k))
      return nil if m.address == 0 # :( too bad, but it works
      Rufus::Tokyo::Map.to_h(m) # which frees the map
    end

    #
    # Returns the number of records in this table db
    #
    def size
      lib.tctdbrnum(@db)
    end

    #
    # Prepares a query instance (block is optional)
    #
    def prepare_query (&block)
      q = TableQuery.new(self)
      block.call(q) if block
      q
    end

    #
    # Prepares and runs a query, returns a ResultSet instance
    # (takes care of freeing the query structure)
    #
    def do_query (&block)
      q = prepare_query(&block)
      rs = q.run
      q.free
      rs
    end

    #
    # Prepares and runs a query, returns an array of hashes (all Ruby)
    # (takes care of freeing the query and the result set structures)
    #
    def query (&block)
      rs = do_query(&block)
      a = rs.to_a
      rs.free
      a
    end

    #
    # Returns the actual pointer to the Tokyo Cabinet table
    #
    def pointer
      @db
    end

    protected

    #
    # Obviously something got wrong, let's ask the db about it and raise
    # a TokyoError
    #
    def raise_error

      err_code = lib.tctdbecode(@db)
      err_msg = lib.tctdberrmsg(err_code)

      raise TokyoError, "(err #{err_code}) #{err_msg}"
    end
  end

  #
  # A query on a Tokyo Cabinet table db
  #
  class TableQuery
    include CabinetLibMixin

    OPERATORS = {

      # strings...

      :streq => 0, # string equality
      :eq => 0,
      :eql => 0,
      :equals => 0,

      :strinc => 1, # string include
      :inc => 1, # string include
      :includes => 1, # string include

      :strbw => 2, # string begins with
      :strew => 3, # string ends with

      :strand => 4, # string which include all the tokens in the given exp
      :and => 4,

      :stror => 5, # string which include at least one of the tokens
      :or => 5,

      :stroreq => 6, # string which is equal to at least one token

      :strorrx => 7, # string which matches the given regex
      :regex => 7,
      :matches => 7,

      # numbers...

      :numgt => 8, # greater than
      :gt => 8,
      :numge => 9, # greater or equal
      :ge => 9,
      :gte => 9,
      :numlt => 10, # greater or equal
      :lt => 10,
      :numle => 11, # greater or equal
      :le => 11,
      :lte => 11,
      :numbt => 12, # a number between two tokens in the given exp
      :bt => 12,
      :between => 12,

      :numoreq => 13 # number which is equal to at least one token
    }

    TDQQCNEGATE = 1 << 24
    TDQQCNOIDX = 1 << 25

    DIRECTIONS = {
      :strasc => 0,
      :strdesc => 1,
      :asc => 0,
      :desc => 1,
      :numasc => 2,
      :numdesc => 3
    }

    #
    # Creates a query for a given Rufus::Tokyo::Table
    #
    def initialize (table)
      @table = table
      @query = lib.tctdbqrynew(@table.pointer)
      @opts = {}
    end

    def add (colname, operator, val, negate=false)
      op = OPERATORS[operator]
      op = op | TDQQCNEGATE if negate
      lib.tctdbqryaddcond(@query, colname, OPERATORS[operator], val)
    end
    alias :add_condition :add

    #
    # Sets the max number of records to return for this query.
    #
    # (sorry no 'offset' as of now)
    #
    def limit (i)
      lib.tctdbqrysetmax(@query, i)
    end

    #
    # Sets the sort order for the result of the query
    #
    def order_by (colname, direction)
      lib.tctdbqrysetorder(@query, colname, DIRECTIONS[direction])
    end

    #
    # When set to true, only the primary keys of the matching records will
    # be returned.
    #
    def pk_only (on=true)
      @opts[:pk_only] = on
    end

    #
    # When set to true, the :pk (primary key) is not inserted in the record
    # (hashes) returned
    #
    def no_pk (on=true)
      @opts[:no_pk] = on
    end

    #
    # Runs this query (returns a TableResultSet instance)
    #
    def run
      TableResultSet.new(@table, lib.tctdbqrysearch(@query), @opts)
    end

    #
    # Frees this data structure
    #
    def free
      lib.tctdbqrydel(@query)
      @query = nil
    end

    alias :close :free
    alias :destroy :free
  end

  #
  # The thing queries return
  #
  class TableResultSet
    include CabinetLibMixin
    include Enumerable

    def initialize (table, list_pointer, query_opts)
      @table = table
      @list = list_pointer
      @opts = query_opts
    end

    #
    # Returns the count of element in this result set
    #
    def size
      lib.tclistnum(@list)
    end

    alias :length :size

    #
    # The classical each
    #
    def each
      (0..size-1).each do |i|
        pk = lib.tclistval2(@list, i)
        if @opts[:pk_only]
          yield(pk)
        else
          val = @table[pk]
          val[:pk] = pk unless @opts[:no_pk]
          yield(val)
        end
      end
    end

    #
    # Returns an array of hashes
    #
    def to_a
      collect { |m| m }
    end

    #
    # Frees this query (the underlying Tokyo Cabinet list structure)
    #
    def free
      lib.tclistdel(@list)
      @list = nil
    end

    alias :close :free
    alias :destroy :free
  end
end

