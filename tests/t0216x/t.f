      include 'factorial.f'

      program t
      implicit none
      integer::f
      call factorial(5,f)
      print '(i0)',f
      end program t
      
