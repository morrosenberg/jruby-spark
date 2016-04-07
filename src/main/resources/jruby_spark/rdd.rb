module JRubySpark

  class RDDBase < Delegator
    def initialize jrdd
      super
    end

    def __getobj__
      @jrdd
    end

    def __setobj__(obj)
      @jrdd = obj
    end

    protected
    def callJava method, fclazz, f, args = []
      args = [create_func!(fclazz, f)] + args
      @jrdd.__send__(method, *args)
    end

    def create_func! fclazz, f
      raise RDDError, 'not a lambda' unless Proc === f || Symbol === f
      payload = Marshal.dump(f).to_java_bytes
      fclazz.new(payload)
    end

  end

  class RDD < RDDBase
  end

  class PairRDD < RDDBase
  end

  class DoubleRDD < RDDBase
  end

  module DefHelper
    # create delegator method as:
    # def map f = nil, &block
    #   f ||= Proc.new(block) if block_given?
    #   callJava :map, JFunction, f
    # end
    def def_transform name, fclazz, ret_clazz = RDD, default_func = nil
      define_method(name) do |f = default_func, &block|
        f ||= block if block
        if ret_clazz
          ret_clazz.new(callJava(name, fclazz, f))
        else
          callJava(name, fclazz, f)
        end
      end
    end

    def wrap_return name, ret_clazz = self
      define_method(name) do |*args|
        ret_clazz.new(@jrdd.__send__(name, *args))
      end
    end

    def merge_rdd name, from_clazz = self, to_clazz = self
      define_method(name) do |rdd, *args|
        raise RDDError, "not a #{from_rdd}" unless from_clazz === rdd
        to_clazz.new(@jrdd.__send__(name, rdd.__getobj__, *args))
      end
    end

    def _clean_object e
        if RubyObjectWrapper === e
          t = e.get
          # XXX java null == nil is false? maybe a bug in jruby
          t.nil? ? nil : t
        else
          e
        end
    end

  end

  module RDDLike
    extend DefHelper

    def aggregate zero, seqOp, combOp
      @jrdd.__send__(:aggregate, zero, create_func!(JFunction2, seqOp), create_func!(JFunction2, combOp))
    end

    merge_rdd :cartesian, RDD, PairRDD

    def collect
      @jrdd.collect.map {|e| RDDLike._clean_object e}
    end

    def_transform :flat_map, JFlatMapFunction
    def_transform :flat_map_to_double, JFlatMapFunction, DoubleRDD
    # flat_map_to_pair
    def fold zero, f = nil, &block
      f ||= block if block
      RDD.new @jrdd.fold(zero, create_func!(JFunction2, f))
    end
    def_transform :foreach_partition, JVoidFunction, nil

    def group_by f = nil, num_partitions = nil, &block
      f ||= block if block
      if num_partitions
        PairRDD.new @jrdd.groupBy(create_func!(JFunction, f), num_partitions)
      else
        PairRDD.new @jrdd.groupBy(create_func!(JFunction, f))
      end
    end

    def empty?
      @jrdd.isEmpty
    end

    def_transform :key_by, JFunction, PairRDD

    def_transform :reduce, JFunction2, nil
    def_transform :foreach, JVoidFunction, nil
    def_transform :map, JFunction
    def_transform :map_to_double, JDoubleFunction, DoubleRDD, :to_f
    def_transform :map_to_pair, JPairFunction, PairRDD

    def map_partitions_with_index f = nil, preservesPartitioning = false, &block
      f ||= block if block
      to_iter_f2 = lambda {|v1, v2| Helpers.to_iter f.call(v1, v2) }
      RDD.new @jrdd.mapPartitionsWithIndex(create_func!(JFunction2, to_iter_f2), preservesPartitioning)
    end

    def map_partitions f = nil, preservesPartitioning = false, &block
      f ||= block if block
      RDD.new @jrdd.mapPartitions(create_func!(JFlatMapFunction, f), preservesPartitioning)
    end

    def tree_aggregate zero, seqOp, combOp, depth = 2
      @jrdd.treeAggregate zero, create_func!(JFunction2, seqOp), create_func!(JFunction2, combOp), depth
    end

    def tree_reduce zero, f = nil, depth = 2, &block
      f ||= block if block
      @jrdd.treeReduce zero, create_func!(JFunction2, f), depth
    end

    def zip(other)
      PairRDD.new(@jrdd.zip(other.__getobj__))
    end

    def zip_with_index
      PairRDD.new @jrdd.zipWithIndex
    end

    def zip_with_unique_id
      PairRDD.new @jrdd.zipWithUniqueId
    end

    def inspect
      "#<#{self.class}: #{@jrdd.inspect}>"
    end
  end

  class RDD
    extend DefHelper
    include RDDLike
    # def filter &block
    #   f = Proc.new block
    #   wrap = lambda {|x|
    #     f.call(x) ? true.to_java : false.to_java
    #   }
    #   RDD.new(callJava(:filter, JFunction, wrap))
    # end

    merge_rdd :intersection

    wrap_return :cache
    wrap_return :coalesce
    wrap_return :distinct
    wrap_return :persist
    def_transform :filter, JFunction

    def random_split weights, seed = rand(100000000)
      @jrdd.randomSplit(weights, seed).map{|e| RDD.new(e)}
    end

    wrap_return :repartition
    wrap_return :sample

    def sort_by f = nil, ascending = true, num_partitions = nil, &block
      f ||= block if block
      num_partitions ||= @jrdd.getNumPartitions
      RDD.new(@jrdd.sortBy(create_func!(JFunction, f), ascending, num_partitions))
    end

    merge_rdd :substract
    merge_rdd :union
    wrap_return :unpersist

    def to_double_rdd
      DoubleRDD.from_rdd self
    end
  end

  class DoubleRDD
    extend DefHelper
    include RDDLike

    def self.from_rdd rdd
      raise RDDError, 'not an rdd' unless RDD === rdd
      @jrdd = JavaDoubleRDD.fromRDD rdd.__getobj__.rdd
    end

    wrap_return :cache
    wrap_return :coalesce
    wrap_return :distinct
    def_transform :filter, JFunction

    merge_rdd :intersection
    wrap_return :persist
    wrap_return :repartition
    wrap_return :sample

    merge_rdd :substract
    merge_rdd :union
    wrap_return :unpersist

  end

  class PairRDD
    extend DefHelper
    include RDDLike

    # TODO aggregatebykey
    wrap_return :cache
    wrap_return :coalesce
    merge_rdd :cogroup, PairRDD, PairRDD

    def collect_as_map
      # XXX how to safely sanity key/values
      h = Hash.new
      @jrdd.collectAsMap.each {|e| h[RDDLike._clean_object(e[0])] = RDDLike._clean_object(e[1])}
      h
    end
    def cogroup *args
      case args.size
      when 1
        PairRDD.new(@jrdd.cogroup(args[0].__getobj__))
      when 2
        if PairRDD === args[1]
          PairRDD.new(@jrdd.cogroup(args[0].__getobj__), args[1].__getobj__)
        else
          PairRDD.new(@jrdd.cogroup(args[0].__getobj__), args[1])
        end
      when 3
        if PairRDD === args[2]
          PairRDD.new(@jrdd.cogroup(args[0].__getobj__), args[1].__getobj__, args[2].__getobj__)
        else
          PairRDD.new(@jrdd.cogroup(args[0].__getobj__), args[1].__getobj__, args[2])
        end
      when 4
          PairRDD.new(@jrdd.cogroup(args[0].__getobj__), args[1].__getobj__, args[2].__getobj__, args[3])
      else
        raise ArgumentError('unexpected argument numbers')
      end
    end

    def combine_by_key(combiner, mergeV, mergeC, num_partitions = nil)
      if num_partitions
        # TODO more overrides
        PairRDD.new(@jrdd.combineByKey(create_func!(JFunction, combiner),
                                       create_func!(JFunction2, mergeV),
                                       create_func!(JFunction2, mergeC),
                                       num_partitions))
      else
        PairRDD.new(@jrdd.combineByKey(create_func!(JFunction, combiner),
                                       create_func!(JFunction2, mergeV),
                                       create_func!(JFunction2, mergeC),
                                      ))
      end
    end

    def_transform :flat_map_values, JFunction, PairRDD

    def fold_by_key(zero, num_partitions = nil, f = nil, &block)
      f ||= block if block
      num_partitions ||= @jrdd.getNumPartitions
      PairRDD.new(@jrdd.foldByKey(zero, num_partitions, create_func!(JFunction2, f)))
    end

    merge_rdd :full_outer_join
    wrap_return :group_by_key

    alias_method :group_with, :cogroup
    merge_rdd :join
    # TODO keys
    wrap_return :left_outer_join

    def_transform :map_values, JFunction, PairRDD
    wrap_return :persist

    def_transform :reduce_by_key, JFunction2, PairRDD
    # TODO reduce by key
    def reduce_by_key_locally
      @jrdd.reduceByKeyLocally(create_func!(JFunction2, f))
    end

    wrap_return :repartition
    wrap_return :repartition_and_sort_within_partitions

    merge_rdd :right_outer_join
    wrap_return :sample
    wrap_return :sample_by_key
    wrap_return :sample_by_key_exact
    wrap_return :sort_by_key
    merge_rdd :substract
    merge_rdd :substract_by_key
    wrap_return :unpersist
    wrap_return :values, RDD
  end

  class SparkContext < Delegator
    def initialize conf
      ctx = JavaSparkContext.new conf
      @jctx = ctx
    end

    def __getobj__
      @jctx
    end

    def text_file(path, min_partitions = nil)
      if min_partitions
        RDD.new(@jctx.textFile(path, min_partitions))
      else
        RDD.new(@jctx.textFile(path))
      end
    end

    def whole_text_files(path, min_partitions)
      RDD.new(@jctx.wholeTextFiles(path, min_partitions))
    end

    def parallelize(e, num_partitions = nil)
      if num_partitions
        RDD.new @jctx.parallelize(e.to_a, num_partitions)
      else
        RDD.new @jctx.parallelize(e.to_a)
      end
    end

    def parallelize_doubles(e, num_partitions = nil)
      if num_partitions
        DoubleRDD.new @jctx.parallelizeDoubles(e.to_a, num_partitions)
      else
        DoubleRDD.new @jctx.parallelizeDoubles(e.to_a)
      end
    end

    def parallelize_pairs(e, num_partitions = nil)
      if num_partitions
        PairRDD.new @jctx.parallelizePairs(e.to_a, num_partitions)
      else
        PairRDD.new @jctx.parallelizePairs(e.to_a)
      end
    end


    def inspect
      "#<#{self.class} jctx=#{@jctx.inspect}>"
    end
  end
end