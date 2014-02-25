module Intrinsics

  def intrinsics
    {
      'abs'                => :interior,
      'achar'              => :interior,
      'acos'               => :interior,
      'adjustl'            => :interior,
      'adjustr'            => :interior,
      'aimag'              => :interior,
      'aint'               => :interior,
      'all'                => :interior,
      'allocated'          => :complete,
      'anint'              => :interior,
      'any'                => :interior,
      'asin'               => :interior,
      'associated'         => :interior,
      'atan'               => :interior,
      'atan2'              => :interior,
      'bit_size'           => :complete,
      'btest'              => :interior,
      'ceiling'            => :interior,
      'char'               => :interior,
      'cmplx'              => :interior,
      'conjg'              => :interior,
      'cos'                => :interior,
      'cosh'               => :interior,
      'count'              => :interior,
      'cshift'             => :error,
      'date_and_time'      => :error,
      'dble'               => :interior,
      'digits'             => :complete,
      'dim'                => :interior,
      'dot_product'        => :interior,
      'dprod'              => :interior,
      'eoshift'            => :error,
      'epsilon'            => :complete,
      'exp'                => :interior,
      'exponent'           => :interior,
      'floor'              => :interior,
      'fraction'           => :interior,
      'huge'               => :complete,
      'iachar'             => :interior,
      'iand'               => :interior,
      'ibclr'              => :interior,
      'ibits'              => :interior,
      'ibset'              => :interior,
      'ichar'              => :interior,
      'ieor'               => :interior,
      'index'              => :interior,
      'int'                => :interior,
      'ior'                => :interior,
      'ishft'              => :interior,
      'ishftc'             => :interior,
      'kind'               => :complete,
      'lbound'             => :interior,
      'len'                => :complete,
      'len_trim'           => :interior,
      'lge'                => :interior,
      'lgt'                => :interior,
      'lle'                => :interior,
      'llt'                => :interior,
      'log'                => :interior,
      'log10'              => :interior,
      'logical'            => :interior,
      'matmul'             => :error,
      'max'                => :interior,
      'maxexponent'        => :complete,
      'maxloc'             => :interior,
      'maxval'             => :interior,
      'merge'              => :interior,
      'min'                => :interior,
      'minexponent'        => :complete,
      'minloc'             => :interior,
      'minval'             => :interior,
      'mod'                => :interior,
      'modulo'             => :interior,
      'mvbits'             => :interior,
      'nearest'            => :interior,
      'nint'               => :interior,
      'not'                => :interior,
      'pack'               => :error,
      'precision'          => :complete,
      'present'            => :complete,
      'product'            => :error,
      'radix'              => :complete,
      'random_number'      => :interior,
      'random_seed'        => :interior,
      'range'              => :complete,
      'real'               => :interior,
      'repeat'             => :error,
      'reshape'            => :error,
      'rrspacing'          => :interior,
      'scale'              => :interior,
      'scan'               => :interior,
      'selected_int_kind'  => :error,
      'selected_real_kind' => :error,
      'set_exponent'       => :interior,
      'shape'              => :interior,
      'sign'               => :interior,
      'sin'                => :interior,
      'sinh'               => :interior,
      'size'               => :interior,
      'spacing'            => :interior,
      'spread'             => :error,
      'sqrt'               => :interior,
      'sum'                => :interior,
      'system_clock'       => :error,
      'tan'                => :interior,
      'tanh'               => :interior,
      'tiny'               => :complete,
      'transfer'           => :interior,
      'transpose'          => :error,
      'trim'               => :error,
      'ubound'             => :interior,
      'unpack'             => :error,
      'verify'             => :interior
    }
  end

end
