program p
  implicit none
  integer::x6h=1
  call s(a=x6h, b=2) ! don't interpret '6h' as start of hollerith!
contains
  subroutine s(a,b)
    integer::a,b
    print *,a,b
  end subroutine s
end program p
