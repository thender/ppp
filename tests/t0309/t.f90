program t1
  implicit none
! inquire stmt 'blank' specifier (zero)
! and character variable in open stmt
  character*4::a, endprogram='zero'
  open (56, status='new', file='tmpfile', blank=endprogram)
  inquire (56, blank=a)
  print *,a
 endprogram t1

