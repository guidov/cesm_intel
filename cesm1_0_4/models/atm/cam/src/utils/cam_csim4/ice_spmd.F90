module ice_spmd

  !-----------------------------------------------------------------------
  ! MPI initialization (number of cpus, processes, tids, etc)
  !-----------------------------------------------------------------------

  use shr_kind_mod, only: r8 => shr_kind_r8
  implicit none
  save

  ! Default settings valid even if there is no spmd 

  logical, public :: masterproc       ! proc 0 logical for printing msgs
  integer, public :: iam              ! processor number
  integer, public :: npes             ! number of processors for ice
  integer, public :: mpicom           ! communicator group for ice

#include <mpif.h>  

contains

  subroutine ice_spmd_init( ice_mpicom )

    !-----------------------------------------------------------------------
    !
    ! Arguments
    !
    integer, intent(in) :: ice_mpicom
    !
    ! Local variables
    !
    integer :: ier
    !-----------------------------------------------------------------------

    ! Initialize mpi and set communication group

    mpicom = ice_mpicom

#if (defined SPMD)
    ! Get my processor id

    call mpi_comm_rank(mpicom, iam, ier)
    if (iam==0) then
       masterproc = .true.
    else
       masterproc = .false.
    end if

    ! Get number of processors

    call mpi_comm_size(mpicom, npes, ier)

#else

    iam = 0
    masterproc = .true.
    npes = 1

#endif

  end subroutine ice_spmd_init

end module ice_spmd
