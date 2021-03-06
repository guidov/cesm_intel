!===============================================================================
! SVN $Id: seq_frac_mct.F90 28202 2011-04-29 23:30:47Z tcraig $
! SVN $URL: https://svn-ccsm-models.cgd.ucar.edu/drv/seq_mct/branch_tags/cesm1_0_4_rel_tags/cesm1_0_4_n01_drvseq3_1_48/driver/seq_frac_mct.F90 $
!===============================================================================
!BOP ===========================================================================
!
! !MODULE: seq_frac_mct -- handles surface fractions.
!
!  Fraction Notes: tcraig, august 2008
!
!  the fractions fields are now afrac, ifrac, ofrac, lfrac, and lfrin.
!    afrac = fraction of atm on a grid
!    lfrac = fraction of lnd on a grid
!    ifrac = fraction of ice on a grid
!    ofrac = fraction of ocn on a grid
!    lfrin = land fraction defined by the land model
!    ifrad = fraction of ocn on a grid at last radiation time
!    ofrad = fraction of ice on a grid at last radiation time
!      afrac, lfrac, ifrac, and ofrac are the self-consistent values in the 
!      system.  lfrin is the fraction on the land grid and is allowed to
!      vary from the self-consistent value as descibed below.  ifrad
!      and ofrad are needed for the swnet calculation.
!  the fractions fields are defined for each grid in the fraction bundles as 
!    needed as follows.
!    character(*),parameter :: fraclist_a = 'afrac:ifrac:ofrac:lfrac:lfrin'
!    character(*),parameter :: fraclist_o = 'afrac:ifrac:ofrac:ifrad:ofrad'
!    character(*),parameter :: fraclist_i = 'afrac:ifrac:ofrac'
!    character(*),parameter :: fraclist_l = 'afrac:lfrac:lfrin'
!    character(*),parameter :: fraclist_g = 'gfrac'
!
!  we assume ocean and ice are on the same grids, same masks
!  we assume ocn2atm and ice2atm are masked maps
!  we assume lnd2atm is a global map
!  we assume that the ice fraction evolves in time but that
!    the land model fraction does not.  the ocean fraction then
!    is just the complement of the ice fraction over the region
!    of the ocean/ice mask.
!  we assume that component domains are filled with the total 
!    potential mask/fraction on that grid, but that the fractions
!    sent at run time are always the relative fraction covered.
!    for example, if an ice cell can be up to 50% covered in 
!    ice and 50% land, then the ice domain should have a fraction
!    value of 0.5 at that grid cell.  at run time though, the ice
!    fraction will be between 0.0 and 1.0 meaning that grid cells
!    is covered with between 0.0 and 0.5 by ice.  the "relative" fractions 
!    sent at run-time are corrected by the model to be total fractions
!    such that
!  in general, on every grid,
!              fractions_*(afrac) = 1.0
!              fractions_*(ifrac) + fractions_*(ofrac) + fractions_*(lfrac) = 1.0
!  where fractions_* are a bundle of fractions on a particular grid and 
!    *frac (ie afrac) is the fraction of a particular component in the bundle.
!
!  the fractions are computed fundamentally as follows (although the 
!    detailed implementation might be slightly different)
!  initialization (frac_init):
!    afrac is set on all grids
!      fractions_a(afrac) = 1.0
!      fractions_o(afrac) = mapa2o(fractions_a(afrac))
!      fractions_i(afrac) = mapa2i(fractions_a(afrac))
!      fractions_l(afrac) = mapa2l(fractions_a(afrac))
!    initially assume ifrac on all grids is zero
!      fractions_*(ifrac) = 0.0
!    fractions/masks provided by surface components
!      fractions_o(ofrac) = dom_o(frac)  ! ocean "mask"
!      fractions_l(lfrin) = dom_l(frac)  ! land model fraction
!    then mapped to the atm model
!      fractions_a(ofrac) = mapo2a(fractions_o(ofrac))
!      fractions_a(lfrin) = mapl2a(fractions_l(lfrin))
!    and a few things are then derived
!      fractions_a(lfrac) = 1.0 - fractions_a(ofrac)
!        this is truncated to zero for very small values (< 0.001)
!        to attempt to preserve non-land gridcells.
!      fractions_l(lfrac) = mapa2l(fractions_a(lfrac))
!    one final term is computed
!      dom_a(ascale) = fractions_a(lfrac)/fractions_a(lfrin)
!      dom_l(ascale) = mapa2l(dom_a(ascale))
!        these are used to correct land fluxes in budgets and lnd2rtm coupling
!        and are particularly important when the land model is running on 
!        a different grid than the atm model.  in the old system, this term
!        was treated as effectively 1.0 since there was always a check that
!        fractions_a(lfrac) ~ fractions_a(lfrin), namely that the land model
!        provided a land frac that complemented the ocean grid.  this is
!        no longer a requirement in this new system and as a result, the
!        ascale term can be thought of as a rescaling of the land fractions
!        in the land model to be exactly complementary to the ocean model
!        on whatever grid it may be running.
!  run-time (frac_set):
!    update fractions on ice grid
!      fractions_i(ifrac) = i2x_i(Si_ifrac)  ! ice frac from ice model
!      fractions_i(ofrac) = 1.0 - fractions_i(ifrac)
!        note: the relative fractions are corrected to total fractions
!      fractions_o(ifrac) = mapi2o(fractions_i(ifrac))
!      fractions_o(ofrac) = mapi2o(fractions_i(ofrac))
!      fractions_a(ifrac) = mapi2a(fractions_i(ifrac))
!      fractions_a(ofrac) = mapi2a(fractions_i(ofrac))
! 
!  fractions used in merging are as follows
!    mrg_x2a uses fractions_a(lfrac,ofrac,ifrac)
!    mrg_x2o needs to use fractions_o(ofrac,ifrac) normalized to one
!      normalization happens in mrg routine
!
!  fraction corrections in mapping are as follows
!    mapo2a uses *fractions_o(ofrac) and /fractions_a(ofrac)
!    mapi2a uses *fractions_i(ifrac) and /fractions_a(ifrac)
!    mapl2a uses *fractions_l(lfrin) and /fractions_a(lfrin)
!    mapa2* should use *fractions_a(afrac) and /fractions_*(afrac) but this
!      has been defered since the ratio always close to 1.0
!
!  budgets use the standard afrac, ofrac, ifrac, and lfrac to compute
!    quantities except in the land budget which uses lfrin multiplied
!    by the scale factor, dom_l(ascale) to compute budgets.
!
!  fraction and domain checks
!    initialization:
!      dom_i = mapo2i(dom_o)  ! lat, lon, mask, area
!      where fractions_a(lfrac) > 0.0, fractions_a(lfrin) is also > 0.0
!         this ensures the land will provide data everywhere the atm needs it
!         and allows the land frac to be subtlely different from the
!         land fraction specified in the atm.
!      dom_a = mapl2a(dom_l)  ! if atm/lnd same grids
!      dom_a = mapo2a(dom_o)  ! if atm/ocn same grids
!      dom_a = mapi2a(dom_i)  ! if atm/ocn same grids
!      0.0-eps < fractions_*(*) < 1.0+eps
!      fractions_l(lfrin) = fractions_l(lfrac) 
!        only if atm/lnd same grids (but this is not formally required)
!        this is needed until dom_l(ascale) is sent to the land model
!        as an additional field for use in l2r mapping.
!    run time:
!      fractions_a(lfrac) + fractions_a(ofrac) + fractions_a(ifrac) ~ 1.0
!      0.0-eps < fractions_*(*) < 1.0+eps
!    
!!
!
! !REVISION HISTORY:
!    2007-may-07 - M. Vertenstein - initial port to cpl7.
!
! !INTERFACE: ------------------------------------------------------------------
                                                                                      
module seq_frac_mct

! !USES:

  use shr_kind_mod     , only: R8 => SHR_KIND_R8
  use shr_sys_mod
  use shr_const_mod

  use mct_mod
  use seq_cdata_mod
  use map_iceocn_mct
  use map_atmice_mct
  use map_atmocn_mct
  use map_atmlnd_mct
  use seq_comm_mct, only: logunit, loglevel

  implicit none
  private
  save

! !PUBLIC TYPES:

  ! none

! !PUBLIC MEMBER FUNCTIONS:

  public seq_frac_init
  public seq_frac_set

! !PUBLIC DATA MEMBERS:

!EOP

! !LOCAL DATA

#ifdef CPP_VECTOR
  logical :: usevector = .true.
#else
  logical :: usevector = .false.
#endif
  
#ifdef SYSUNICOS
  logical :: usealltoall = .true.
#else
  logical :: usealltoall = .false.
#endif

  integer, private :: seq_frac_debug = 1
  logical, private :: seq_frac_abort = .true.
  logical, private :: seq_frac_dead

  !--- standard ---
  real(r8),parameter :: eps_fracsum = 1.0e-02   ! allowed error in sum of fracs 
  real(r8),parameter :: eps_fracval = 1.0e-02   ! allowed error in any frac +- 0,1
  real(r8),parameter :: eps_fraclim = 1.0e-03   ! truncation limit in fractions_a(lfrac)
  logical ,parameter :: atm_frac_correct = .false. ! turn on frac correction on atm grid
  !--- standard plus atm fraction consistency ---
!  real(r8),parameter :: eps_fracsum = 1.0e-12   ! allowed error in sum of fracs 
!  real(r8),parameter :: eps_fracval = 1.0e-02   ! allowed error in any frac +- 0,1
!  real(r8),parameter :: eps_fraclim = 1.0e-03   ! truncation limit in fractions_a(lfrac)
!  logical ,parameter :: atm_frac_correct = .true. ! turn on frac correction on atm grid
  !--- unconstrained and area conserving? ---
!  real(r8),parameter :: eps_fracsum = 1.0e-12   ! allowed error in sum of fracs 
!  real(r8),parameter :: eps_fracval = 1.0e-02   ! allowed error in any frac +- 0,1
!  real(r8),parameter :: eps_fraclim = 1.0e-20   ! truncation limit in fractions_a(lfrac)
!  logical ,parameter :: atm_frac_correct = .true. ! turn on frac correction on atm grid

  private seq_frac_check

!===============================================================================
contains
!===============================================================================

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: seq_frac_init 
!
! !DESCRIPTION:
!    Initialize fraction attribute vectors and necessary ocn/ice domain
!    fraction input if appropriate
!
! !REVISION HISTORY:
!    2007-may-07 - M. Vertenstein - initial cpl7 version.
!
! !INTERFACE: ------------------------------------------------------------------

subroutine seq_frac_init(cdata_a, cdata_i, cdata_l, cdata_o, cdata_g, &
                         ice_present, ocn_present, lnd_present, glc_present, &
                         dead_comps, &
                         fractions_a, fractions_i, fractions_l, fractions_o, &
                         fractions_g)

! !INPUT/OUTPUT PARAMETERS:

   type(seq_cdata), intent(in)    :: cdata_a
   type(seq_cdata), intent(in)    :: cdata_i
   type(seq_cdata), intent(in)    :: cdata_l
   type(seq_cdata), intent(in)    :: cdata_o
   type(seq_cdata), intent(in)    :: cdata_g
   logical        , intent(in)    :: ice_present   ! .true. => ocean is present and not aqua_planet
   logical        , intent(in)    :: ocn_present   ! .true. => ocean is present
   logical        , intent(in)    :: lnd_present   ! .true. => land is present
   logical        , intent(in)    :: glc_present   ! .true. => glc is present
   logical        , intent(in)    :: dead_comps    ! .true. => dead models present
   type(mct_aVect), intent(inout) :: fractions_a   ! Fractions on atm grid/decomp
   type(mct_aVect), intent(inout) :: fractions_i   ! Fractions on ice grid/decomp
   type(mct_aVect), intent(inout) :: fractions_l   ! Fractions on lnd grid/decomp
   type(mct_aVect), intent(inout) :: fractions_o   ! Fractions on ocn grid/decomp
   type(mct_aVect), intent(inout) :: fractions_g   ! Fractions on glc grid/decomp

!EOP

   !----- local -----
   integer :: j,n                      ! indices
   integer :: ka, ki, kl, ko, kf, kk   ! indices 
   integer :: lsize                    ! local size of ice av
   integer :: debug_old                ! old debug value
   type(mct_gGrid), pointer :: dom_a   ! pointer to component domain
   type(mct_gGrid), pointer :: dom_i   ! pointer to component domain
   type(mct_gGrid), pointer :: dom_l   ! pointer to component domain
   type(mct_gGrid), pointer :: dom_o   ! pointer to component domain
   type(mct_gGrid), pointer :: dom_g   ! pointer to component domain

   character(*),parameter :: fraclist_a = 'afrac:ifrac:ofrac:lfrac:lfrin'
   character(*),parameter :: fraclist_o = 'afrac:ifrac:ofrac:ifrad:ofrad'
   character(*),parameter :: fraclist_i = 'afrac:ifrac:ofrac'
   character(*),parameter :: fraclist_l = 'afrac:lfrac:lfrin'
   character(*),parameter :: fraclist_g = 'gfrac'

   !----- formats -----
   character(*),parameter :: subName = '(seq_frac_init) '

!-------------------------------------------------------------------------------
!
!-------------------------------------------------------------------------------

   debug_old = seq_frac_debug
   seq_frac_debug = 2

   seq_frac_dead = dead_comps

   ! Initialize fractions on atm grid/decomp (initialize ice fraction to zero)

!  if (atm_present) then
      call seq_cdata_setptrs(cdata_a, dom=dom_a)

      lSize = mct_aVect_lSize(dom_a%data)
      call mct_aVect_init(fractions_a,rList=fraclist_a,lsize=lsize)
      call mct_aVect_zero(fractions_a)

      ka = mct_aVect_indexRa(fractions_a,"afrac",perrWith=subName)
      fractions_a%rAttr(ka,:) = 1.0_r8
!  endif

   ! Initialize fractions on glc grid decomp, just an initial "guess", updated later

   if (glc_present) then
      call seq_cdata_setptrs(cdata_g, dom=dom_g)

      lSize = mct_aVect_lSize(dom_g%data)
      call mct_aVect_init(fractions_g,rList=fraclist_g,lsize=lsize)
      call mct_aVect_zero(fractions_g)
      fractions_g%rAttr(:,:) = 1.0_r8
      
   end if
      
   ! Initialize fractions on land grid decomp, just an initial "guess", updated later

   if (lnd_present) then
      call seq_cdata_setptrs(cdata_l, dom=dom_l)

      lSize = mct_aVect_lSize(dom_l%data)
      call mct_aVect_init(fractions_l,rList=fraclist_l,lsize=lsize)
      call mct_aVect_zero(fractions_l)
      
      kk = mct_aVect_indexRA(fractions_l,"lfrin",perrWith=subName)
      kf = mct_aVect_indexRA(dom_l%data ,"frac" ,perrWith=subName)
      fractions_l%rAttr(kk,:) = dom_l%data%rAttr(kf,:)

      call map_lnd2atm_mct(cdata_l, fractions_l, cdata_a, fractions_a, fluxlist='lfrin')
      call map_atm2lnd_mct(cdata_a, fractions_a, cdata_l, fractions_l, fluxlist='afrac')

   end if
      
   ! Initialize fractions on ice grid/decomp (initialize ice fraction to zero)

   if (ice_present) then
      call seq_cdata_setptrs(cdata_i, dom=dom_i)

      lSize = mct_aVect_lSize(dom_i%data)
      call mct_aVect_init(fractions_i,rList=fraclist_i,lsize=lsize)
      call mct_aVect_zero(fractions_i)
      
      ko = mct_aVect_indexRa(fractions_i,"ofrac",perrWith=subName)	
      kf = mct_aVect_indexRA(dom_i%data ,"frac" ,perrWith=subName)
      fractions_i%rAttr(ko,:) = dom_i%data%rAttr(kf,:)

      call map_ice2atm_mct(cdata_i, fractions_i, cdata_a, fractions_a, fluxlist='ofrac')

   end if

   ! Initialize fractions on ocean grid/decomp (initialize ice fraction to zero)
   ! These are initialize the same as for ice

   if (ocn_present) then
      call seq_cdata_setptrs(cdata_o, dom=dom_o)
      
      lSize = mct_aVect_lSize(dom_o%data)
      call mct_aVect_init(fractions_o,rList=fraclist_o,lsize=lsize)
      call mct_aVect_zero(fractions_o)
      
      if (ice_present) then
         call map_ice2ocn_mct(cdata_i, fractions_i, cdata_o, fractions_o, fluxlist='ofrac')
      else
         ko = mct_aVect_indexRa(fractions_o,"ofrac",perrWith=subName)	
         kf = mct_aVect_indexRA(dom_o%data ,"frac" ,perrWith=subName)
         fractions_o%rAttr(ko,:) = dom_o%data%rAttr(kf,:)
         call map_ocn2atm_mct(cdata_o, fractions_o, cdata_a, fractions_a, fluxlist='ofrac')
      endif

      call map_atm2ocn_mct(cdata_a, fractions_a, cdata_o, fractions_o, fluxlist='afrac')
      if (ice_present) then
          ! --- this should be an atm2ice call above, but atm2ice doesn't work
          call map_ocn2ice_mct(cdata_o, fractions_o, cdata_i, fractions_i, fluxlist='afrac')
      endif

   end if

   ! --- Set ofrac and lfrac on atm grid.  These should actually be mapo2a of
   !     ofrac and lfrac but we can't map lfrac from o2a due to masked mapping
   !     weights.  So we have to settle for a residual calculation that is
   !     truncated to zero to try to preserve "all ocean" cells.

   ka = mct_aVect_indexRa(fractions_a,"afrac",perrWith=subName)
   ki = mct_aVect_indexRa(fractions_a,"ifrac",perrWith=subName)	
   kl = mct_aVect_indexRa(fractions_a,"lfrac",perrWith=subName)
   ko = mct_aVect_indexRa(fractions_a,"ofrac",perrWith=subName)	
   kk = mct_aVect_indexRa(fractions_a,"lfrin",perrWith=subName)	
   lSize = mct_aVect_lSize(fractions_a)

   if (ice_present .or. ocn_present) then
      do n = 1,lsize
         fractions_a%rAttr(kl,n) = 1.0_r8 - fractions_a%rAttr(ko,n)
         if (abs(fractions_a%rAttr(kl,n)) < eps_fraclim) then
            fractions_a%rAttr(kl,n) = 0.0_r8
            if (atm_frac_correct) fractions_a%rAttr(ko,n) = 1.0_r8
         endif
      enddo
   else if (lnd_present) then
      do n = 1,lsize
         fractions_a%rAttr(kl,n) = fractions_a%rAttr(kk,n)
         fractions_a%rAttr(ko,n) = 1.0_r8 - fractions_a%rAttr(kl,n)
         if (abs(fractions_a%rAttr(ko,n)) < eps_fraclim) then
            fractions_a%rAttr(ko,n) = 0.0_r8
            if (atm_frac_correct) fractions_a%rAttr(kl,n) = 1.0_r8
         endif
      enddo
   endif

   ! --- finally, set fractions_l(lfrac) from fractions_a(lfrac)

   if (lnd_present) then
      call map_atm2lnd_mct(cdata_a, fractions_a, cdata_l, fractions_l, fluxlist='lfrac')
   end if

   if (lnd_present) call seq_frac_check(fractions_l,'lnd init')
   if (glc_present) call seq_frac_check(fractions_g,'glc init')
   if (ice_present) call seq_frac_check(fractions_i,'ice init')
   if (ocn_present) call seq_frac_check(fractions_o,'ocn init')
   if (lnd_present.or.ice_present.or.ocn_present) &
                    call seq_frac_check(fractions_a,'atm init')
   seq_frac_debug = debug_old

end subroutine seq_frac_init

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: seq_frac_set
!
! !DESCRIPTION:
!    Update surface fractions
!
! !REVISION HISTORY:
!    2007-may-07 - M. Vertenstein - initial cpl7 version.
!
! !INTERFACE: ------------------------------------------------------------------

subroutine seq_frac_set(i2x_i, cdata_a, cdata_i, cdata_l, cdata_o, cdata_g, &
                         ice_present, ocn_present, lnd_present, glc_present, &
                         fractions_a, fractions_i, fractions_l, fractions_o, &
                         fractions_g)

! !INPUT/OUTPUT PARAMETERS:

   type(mct_aVect), intent(in)    :: i2x_i
   type(seq_cdata), intent(in)    :: cdata_a
   type(seq_cdata), intent(in)    :: cdata_i
   type(seq_cdata), intent(in)    :: cdata_l
   type(seq_cdata), intent(in)    :: cdata_o
   type(seq_cdata), intent(in)    :: cdata_g
   logical        , intent(in)    :: ice_present   ! true => ice is present
   logical        , intent(in)    :: ocn_present   ! true => ocn is present
   logical        , intent(in)    :: lnd_present   ! true => lnd is present
   logical        , intent(in)    :: glc_present   ! true => glc is present
   type(mct_aVect), intent(inout) :: fractions_a   ! Fractions on atm 
   type(mct_aVect), intent(inout) :: fractions_i   ! Fractions on ice 
   type(mct_aVect), intent(inout) :: fractions_l   ! Fractions on lnd 
   type(mct_aVect), intent(inout) :: fractions_o   ! Fractions on ocn 
   type(mct_aVect), intent(inout) :: fractions_g   ! Fractions on glc

!EOP

   !----- local -----
   integer         :: j, n
   integer         :: ki, kl, ka, ko, kf
   integer         :: lsize
   real(r8),allocatable :: fcorr(:)
   type(mct_gGrid), pointer :: dom_i   ! pointer to component domain

   !----- formats -----
   character(*),parameter :: subName = '(seq_frac_set) '

!-------------------------------------------------------------------------------
!
!-------------------------------------------------------------------------------

   !----------------------------------------------------------------------
   ! Update fractions
   ! - Update ice fraction on ice grid first, normalize to total fraction 
   !   available for cover
   ! - Update ocn fraction on ice grid as residual
   ! - Map ice/ocn fractions from ice grid to ocean and atm grids
   !----------------------------------------------------------------------

   if (ice_present) then
      call mct_aVect_copy(i2x_i, fractions_i,"Si_ifrac","ifrac")
      call seq_cdata_setptrs(cdata_i, dom=dom_i)
      ki = mct_aVect_indexRA(fractions_i,"ifrac")
      ko = mct_aVect_indexRA(fractions_i,"ofrac")
      kf = mct_aVect_indexRA(dom_i%data ,"frac" ,perrWith=subName)
      fractions_i%rAttr(ki,:) = fractions_i%rAttr(ki,:) * dom_i%data%rAttr(kf,:)
      fractions_i%rAttr(ko,:) = dom_i%data%rAttr(kf,:) - fractions_i%rAttr(ki,:)
      call seq_frac_check(fractions_i,'ice set')

      if (ocn_present) then
         call map_ice2ocn_mct(cdata_i, fractions_i, cdata_o, fractions_o, fluxlist='ofrac:ifrac')
         call seq_frac_check(fractions_o,'ocn set')
      endif

!      if (atm_present) then
         call map_ice2atm_mct(cdata_i, fractions_i, cdata_a, fractions_a, fluxlist='ofrac:ifrac')
!tcx---  fraction correction, this forces the fractions_a to sum to 1.0_r8.  
!   ---  but it introduces a conservation error in mapping
         if (atm_frac_correct) then
            ki = mct_aVect_indexRA(fractions_a,"ifrac")
            ko = mct_aVect_indexRA(fractions_a,"ofrac")
            kl = mct_aVect_indexRA(fractions_a,"lfrac")
            lSize = mct_aVect_lSize(fractions_a)
            allocate(fcorr(lsize))
            do n = 1,lsize
               if ((fractions_a%rAttr(ki,n)+fractions_a%rAttr(ko,n)) > 0.0_r8) then
                  fcorr(n) = ((1.0_r8-fractions_a%rAttr(kl,n))/(fractions_a%rAttr(ki,n)+fractions_a%rAttr(ko,n)))
               else
                  fcorr(n) = 0.0_r8
               endif
            enddo
            fractions_a%rAttr(ki,:) = fractions_a%rAttr(ki,:) * fcorr(:)
            fractions_a%rAttr(ko,:) = fractions_a%rAttr(ko,:) * fcorr(:)
            deallocate(fcorr)
         endif

         call seq_frac_check(fractions_a,'atm set')
!     endif
   end if

end subroutine seq_frac_set

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: seq_frac_check
!
! !DESCRIPTION:
!    Check surface fractions
!
! !REVISION HISTORY:
!    2008-jun-11 - T. Craig - initial version
!
! !INTERFACE: ------------------------------------------------------------------

subroutine seq_frac_check(fractions,string)

! !INPUT/OUTPUT PARAMETERS:

   type(mct_aVect) , intent(in) :: fractions   ! Fractions datatype
   character(len=*), intent(in), optional :: string      ! character string

!EOP

   !----- local -----
   integer  :: n, lsize
   integer  :: ncnt
   real(r8) :: sum,diff,maxerr
   real(r8) :: aminval,amaxval   ! used for lnd
   real(r8) :: lminval,lmaxval   ! used for lnd
   real(r8) :: ominval,omaxval   ! used for ocn
   real(r8) :: iminval,imaxval   ! used for ice
   real(r8) :: gminval,gmaxval   ! used for glc
   real(r8) :: kminval,kmaxval   ! used for lnd
   real(r8) :: sminval,smaxval   ! used for sum
   integer  :: ka,kl,ki,ko,kg,kk
   character(len=128) :: lstring
   logical :: error

   !----- formats -----
   character(*),parameter :: subName = '(seq_frac_check) '
   character(*),parameter :: F01 = "('(seq_frac_check) ',2a,i8,g26.18)"
   character(*),parameter :: F02 = "('(seq_frac_check) ',2a,2g26.18)"

!-------------------------------------------------------------------------------
!
!-------------------------------------------------------------------------------

   if (present(string)) then
      lstring='['//trim(string)//']'
   else
      lstring=''
   endif

   ka = -1
   kl = -1
   ki = -1
   ko = -1
   kk = -1
   kg = -1
   aminval =  999.0_r8
   amaxval = -999.0_r8
   lminval =  999.0_r8
   lmaxval = -999.0_r8
   iminval =  999.0_r8
   imaxval = -999.0_r8
   ominval =  999.0_r8
   omaxval = -999.0_r8
   gminval =  999.0_r8
   gmaxval = -999.0_r8
   kminval =  999.0_r8
   kmaxval = -999.0_r8
   sminval =  999.0_r8
   smaxval = -999.0_r8

   lsize = mct_avect_lsize(fractions)
   ka = mct_aVect_indexRA(fractions,"afrac",perrWith='quiet')
   kl = mct_aVect_indexRA(fractions,"lfrac",perrWith='quiet')
   ki = mct_aVect_indexRA(fractions,"ifrac",perrWith='quiet')
   ko = mct_aVect_indexRA(fractions,"ofrac",perrWith='quiet')
   kg = mct_aVect_indexRA(fractions,"gfrac",perrWith='quiet')
   kk = mct_aVect_indexRA(fractions,"lfrin",perrWith='quiet')

   if (ka > 0) then
      aminval = minval(fractions%rAttr(ka,:))
      amaxval = maxval(fractions%rAttr(ka,:))
   endif
   if (kl > 0) then
      lminval = minval(fractions%rAttr(kl,:))
      lmaxval = maxval(fractions%rAttr(kl,:))
   endif
   if (ko > 0) then
      ominval = minval(fractions%rAttr(ko,:))
      omaxval = maxval(fractions%rAttr(ko,:))
   endif
   if (ki > 0) then
      iminval = minval(fractions%rAttr(ki,:))
      imaxval = maxval(fractions%rAttr(ki,:))
   endif
   if (kg > 0) then
      gminval = minval(fractions%rAttr(kg,:))
      gmaxval = maxval(fractions%rAttr(kg,:))
   endif
   if (kk > 0) then
      kminval = minval(fractions%rAttr(kk,:))
      kmaxval = maxval(fractions%rAttr(kk,:))
   endif

   ncnt = 0
   maxerr = 0.0_r8
   if (kl > 0 .and. ko > 0 .and. ki > 0) then
      do n = 1,lsize
         sum = fractions%rAttr(ko,n) + fractions%rAttr(kl,n) + fractions%rAttr(ki,n)
         sminval = min(sum,sminval)
         smaxval = max(sum,smaxval)
         diff = abs(1.0_r8 - sum)
         if (diff > eps_fracsum) then
            ncnt = ncnt + 1
            maxerr = max(maxerr, diff)
!tcx debug            write(logunit,*) trim(lstring),' err# ',ncnt,n,lsize,fractions%rAttr(ko,n),fractions%rAttr(kl,n),fractions%rAttr(ki,n),sum
         endif
      enddo
   endif

   error = .false.
   if (ncnt > 0) error = .true.
   if (aminval < 0.0_r8-eps_fracval .or. amaxval > 1.0_r8+eps_fracval) error = .true.
   if (lminval < 0.0_r8-eps_fracval .or. lmaxval > 1.0_r8+eps_fracval) error = .true.
   if (ominval < 0.0_r8-eps_fracval .or. omaxval > 1.0_r8+eps_fracval) error = .true.
   if (iminval < 0.0_r8-eps_fracval .or. imaxval > 1.0_r8+eps_fracval) error = .true.
   if (gminval < 0.0_r8-eps_fracval .or. gmaxval > 1.0_r8+eps_fracval) error = .true.
   if (kminval < 0.0_r8-eps_fracval .or. kmaxval > 1.0_r8+eps_fracval) error = .true.

   if (error .or. seq_frac_debug > 1) then
      if (ka > 0) &
         write(logunit,F02) trim(lstring),' afrac min/max   = ',aminval,amaxval
      if (kl > 0) &
         write(logunit,F02) trim(lstring),' lfrac min/max   = ',lminval,lmaxval
      if (kg > 0) &
         write(logunit,F02) trim(lstring),' gfrac min/max   = ',gminval,gmaxval
      if (ko > 0) &
         write(logunit,F02) trim(lstring),' ofrac min/max   = ',ominval,omaxval
      if (ki > 0) &
         write(logunit,F02) trim(lstring),' ifrac min/max   = ',iminval,imaxval
      if (kk > 0) &
         write(logunit,F02) trim(lstring),' lfrin min/max   = ',kminval,kmaxval
      if (kl > 0 .and. ko > 0 .and. ki > 0) then
         write(logunit,F02) trim(lstring),' sum min/max     = ',sminval,smaxval
         write(logunit,F01) trim(lstring),' sum ncnt/maxerr = ',ncnt,maxerr
      endif
      if (error .and. .not. seq_frac_dead .and. seq_frac_abort) then
         write(logunit,F02) trim(lstring),' ERROR aborting '
         call shr_sys_abort()
      elseif (error) then
         write(logunit,F02) trim(lstring),' ERROR but NOT aborting '
      endif
   endif

end subroutine seq_frac_check

end module seq_frac_mct
