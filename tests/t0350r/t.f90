program t
  character(len=6)::a_b(3)
  data a_b/'Hello ', 5 HW&
    &orld,1h!/
  print *,a_b ! comment
100 format (" Hello ", 5 HW&
      &orld, 2 h !)
  print 100
  call s( 1 &
    & h;)
end program t

subroutine s(c)
  integer,intent(in)::c(1)
  print *,c
end subroutine s
