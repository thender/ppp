program t1
  implicit none
  character*3::a, yes='no'
  open (56, status='new', file='tmpfile', pad=yes)
  inquire (56, pad=a)
  print *,a
  close (56,status='delete')
   endprogram t1
