      program t
      implicit none
    ! inquire stmt 'pad' specifier (yes)
      character*3::a
      open (56, status='new', file='tmpfile', pad='yes')
      inquire (56, pad=a)
      print *,a
      close (56,status='delete')
      endprogram t
