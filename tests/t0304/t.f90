program t1
  implicit none
  character*11::a,b,c,x,y,z
  character*11::form='unformatted'
  open (56, status='new', file='tmpfile', access='sequential', form=form)
  inquire (56, access=a, sequential=b, direct=c, form=x, formatted=y, unformatted=z)

  print *,a
  print *,b
  print *,c
  print *,x
  print *,y
  print *,z

  close (56,status='delete')
  
 endprogram t1

