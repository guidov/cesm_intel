!===============================================================================
! SVN $Id: 
! SVN $URL: 
!===============================================================================
!BOP ===========================================================================
!
! !MODULE: shr_scam_mod.F90 --- Module to handle single column mode share routines.
!
! !DESCRIPTION:
!    Routines needed by drv or several component models for running in single column mode
! 
! !REVISION HISTORY:
!    2010 Nov 05 - E. Kluzek ---- add PIO and file interfaces for getCloseLatLon
!    2007 Sep 14 - B. Kauffman  - svn checkin 
!    2007 Aug 29 - J. Truesdale - first version
!
! !INTERFACE: ------------------------------------------------------------------

module shr_scam_mod

! !USES:

   use shr_kind_mod  ! defines kinds
   use shr_sys_mod   ! system calls
   use shr_file_mod  ! file utilities
   use shr_kind_mod,    only : R8=>SHR_KIND_R8,IN=>SHR_KIND_IN,CL=>SHR_KIND_CL
   use shr_log_mod,     only : s_loglev  => shr_log_Level
   use shr_log_mod,     only : s_logunit => shr_log_Unit

   implicit none

   private           ! By default everything is private to this module

! !PUBLIC TYPES:

   ! no public types

! !PUBLIC MEMBER FUNCTIONS:

   public :: shr_scam_getCloseLatLon ! return lat and lon point/index
   public :: shr_scam_checkSurface   ! check grid fraction in focndomain dataset

   interface shr_scam_getCloseLatLon
     module procedure shr_scam_getCloseLatLonNC
     module procedure shr_scam_getCloseLatLonPIO
     module procedure shr_scam_getCloseLatLonFile
   end interface

! !PUBLIC DATA MEMBERS:

   ! no public data members

!EOP

! !PRIVATE  MEMBER FUNCTIONS:

   private :: is_latlon          ! Check if variable name is a latitude or longitude
   private :: get_close          ! Retrieve the closest lat/lon
   private :: get_latlonindices  ! Get the start/count indices to retreive lat or long

! !PRIVATE DATA MEMBERS:

   save	

!===============================================================================
CONTAINS
!===============================================================================

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: shr_scam_getCloseLatLonNC
!
! !DESCRIPTION:
!    routine to search in netcdf file and return lat and lon point/index closest to target point
!
! !REVISION HISTORY:
!     2010 Nov 05 - E. Kluzek ---- Use is_latlon/get_close/get_latlonindices routines
!     2007 Aug 29 - J. Truesdale - first version
!
! !INTERFACE: ------------------------------------------------------------------

subroutine shr_scam_getCloseLatLonNC(ncid, targetLat,  targetLon, closeLat, closeLon, &
                                     closeLatIdx, closeLonIdx)
! !USES:
   use netcdf
   implicit none

! !INPUT/OUTPUT PARAMETERS:

   integer(IN),intent(in)  :: ncid         ! netcdf id
   real   (R8),intent(in)  :: targetLat    ! find closest latitude to this point
   real   (R8),intent(in)  :: targetLon    ! find closest longitude to this point
   real   (R8),intent(out) :: closeLat     ! returned close lat
   real   (R8),intent(out) :: closeLon     ! returned close lon
   integer(IN),intent(out) :: closeLatIdx  ! index of returned lat point
   integer(IN),intent(out) :: closeLonIdx  ! index of returned lon point

!EOP


   !----- local variables -----
   real   (R8),allocatable          :: lats(:),lons(:)
   integer(IN)                      :: rcode   ! netCDF routine return code
   integer(IN)                      ::  i
   integer(IN)                      ::  len
   integer(IN)                      ::  latlen
   integer(IN)                      ::  lonlen
   integer(IN)                      ::  ndims
   integer(IN)                      ::  nlatdims
   integer(IN)                      ::  nlondims
   integer(IN)                      ::  nvars
   integer(IN)                      ::  nvarid
   integer(IN)                      ::  ndimid
   integer(IN)                      ::  strt(nf90_max_var_dims),count(nf90_max_var_dims)
   integer(IN)                      ::  nlon,nlat
   integer(IN), dimension(nf90_max_var_dims) :: dimids
   character(len=80), allocatable   ::  vars(:)
   character(len=80), allocatable   ::  latdimnames(:)
   character(len=80), allocatable   ::  londimnames(:)
   character(*),parameter :: subname = "(shr_scam_getCloseLatLonNC) "

!-------------------------------------------------------------------------------
! Notes:
!-------------------------------------------------------------------------------

   !--- Get variable info for search ---

   rcode = nf90_inquire(ncid, nVariables=nvars)
   if (rcode /= nf90_noerr) then
      call shr_sys_abort(subname//"ERROR from nf90_inquire ")
   endif

   allocate( vars(nvars) )
   do nvarid = 1, nvars
      rcode = nf90_inquire_variable(ncid, nvarid, vars(nvarid), ndims=ndims,dimids = dimids)
      if (rcode /= nf90_noerr) then
         call shr_sys_abort(subname//"ERROR inquiring about variable "//trim(vars(nvarid)))
      endif
      !-- If latitude variable ---
      if ( is_latlon( vars(nvarid), latitude=.true., varnotdim=.true. ) )then
         nlatdims = ndims
         allocate( latdimnames(ndims) )
         do ndimid =  1,ndims
            rcode = nf90_inquire_dimension(ncid, dimids(ndimid), latdimnames(ndimid), len)
            if (rcode /= nf90_noerr) then
               call shr_sys_abort(subname//"ERROR: Cant read netcdf latitude variable dimension")
            endif
            !--- is this a latitude dimension  ---
            if ( is_latlon( latdimnames(ndimid), latitude=.true., varnotdim=.false. ) )then
               latlen = len
            end if
         end do
      end if
      !-- If longitude variable ---
      if ( is_latlon( vars(nvarid), latitude=.false., varnotdim=.true. ) )then
         nlondims = ndims
         allocate( londimnames(ndims) )
         do ndimid =  1,ndims
            rcode = nf90_inquire_dimension(ncid, dimids(ndimid), londimnames(ndimid), len)
            if (rcode /= nf90_noerr) then
               call shr_sys_abort(subname//"ERROR: Cant read netcdf latitude variable dimension")
            endif
            !--- is this a longitude dimension  ---
            if ( is_latlon( londimnames(ndimid), latitude=.false., varnotdim=.false. ) )then
               lonlen = len
            end if
         end do
      end if
   end do

   !--- Look for/extract lat lon coordinate variables from file ---

   nlat=0
   nlon=0
   nvarid=0

   !--- Loop through all variables until we find lat and lon ---

   do while (nvarid < nvars .and.(nlon.eq.0 .or. nlat.eq.0))
      nvarid=nvarid+1

      !--- Get latitude ---

      if ( is_latlon( vars(nvarid), latitude=.true., varnotdim=.true. ) )then

         call get_latlonindices( latitude=.true., dimnames=latdimnames, ndims=nlatdims, &
                                 nlen=latlen, strt=strt, count=count )
         nlat = latlen
         allocate(lats(nlat))
         rcode= nf90_get_var(ncid, nvarid ,lats, start = strt, count = count)
         if (rcode /= nf90_noerr) then
            call shr_sys_abort( subname//"ERROR: Cant read netcdf latitude")
         endif
      end if

      !--- Get longitude ---

      if ( is_latlon( vars(nvarid), latitude=.false., varnotdim=.true. ) )then
         call get_latlonindices( latitude=.false., ndims=nlondims, dimnames=londimnames, &
                                 nlen=lonlen, strt=strt, count=count )
         nlon = lonlen
         allocate(lons(nlon))
         rcode= nf90_get_var(ncid, nvarid ,lons, start = strt, count = count)
         if (rcode /= nf90_noerr) then
            call shr_sys_abort( subname//"ERROR: Cant read netcdf longitude")
         endif
      end if
   end do

   call get_close( targetLon, targetLat, nlon, lons, nlat, lats, closelonidx, closelatidx )
   closelon=lons(closelonidx)
   closelat=lats(closelatidx)
   deallocate(lats)
   deallocate(lons)
   deallocate( latdimnames )
   deallocate( londimnames )
   deallocate( vars )

   return

end subroutine shr_scam_getCloseLatLonNC

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: shr_scam_getCloseLatLonPIO
!
! !DESCRIPTION:
!    routine to search in netcdf file and return lat and lon point/index 
!    closest to target point using PIO.
!
! !REVISION HISTORY:
!     2010 Nov 01 - E. Kluzek  - first version
!
! !INTERFACE: ------------------------------------------------------------------

subroutine shr_scam_getCloseLatLonPIO(pioid, targetLat,  targetLon, closeLat, closeLon, &
                                      closeLatIdx, closeLonIdx, found )
   use netcdf
   use pio
   implicit none

! !INPUT/OUTPUT PARAMETERS:

   type(file_desc_t), intent(inout) :: pioid        ! pio file ID
   real   (R8),       intent(in)    :: targetLat    ! find closest latitude to this point
   real   (R8),       intent(in)    :: targetLon    ! find closest longitude to this point
   real   (R8),       intent(out)   :: closeLat     ! returned close lat
   real   (R8),       intent(out)   :: closeLon     ! returned close lon
   integer(IN),       intent(out)   :: closeLatIdx  ! index of returned lat point
   integer(IN),       intent(out)   :: closeLonIdx  ! index of returned lon point
   logical, optional, intent(out)   :: found        ! if found answer (will abort if found NOT sent and
                                                    ! it couldn't find the lat/lon dimensions)

!EOP


   !----- local variables -----
   real   (R8),allocatable          :: lats(:),lons(:)
   integer(IN)                      :: rcode   ! netCDF routine return code
   integer(IN)                      ::  i
   integer(IN)                      ::  len      = 0
   integer(IN)                      ::  latlen   = 0
   integer(IN)                      ::  lonlen   = 0
   integer(IN)                      ::  ndims    = 0
   integer(IN)                      ::  nlatdims = 0
   integer(IN)                      ::  nlondims = 0
   integer(IN)                      ::  nvars    = 0
   integer(IN)                      ::  nvarid
   integer(IN)                      ::  ndimid
   integer(IN)                      ::  strt(nf90_max_var_dims),count(nf90_max_var_dims)
   integer(IN)                      ::  nlon = 0, nlat = 0
   logical                          ::  lfound        ! local version of found
   integer(IN), dimension(nf90_max_var_dims) :: dimids
   character(len=80), allocatable   ::  vars(:)
   character(len=80), allocatable   ::  latdimnames(:)
   character(len=80), allocatable   ::  londimnames(:)
   character(*),parameter :: subname = "(shr_scam_getCloseLatLonPIO) "

!-------------------------------------------------------------------------------
! Notes:
!-------------------------------------------------------------------------------

   if ( present(found) )then
      lfound = found
   else
      lfound = .false.
   end if

   !--- Get variable info for search ---

   call pio_seterrorhandling(pioid,PIO_BCAST_ERROR)
   rcode = pio_inquire(pioid, nVariables=nvars)
   if (rcode /= PIO_noerr) then
      call shr_sys_abort(subname//"ERROR from PIO_inquire ")
   endif

   allocate( vars(nvars) )
   do nvarid = 1, nvars
      rcode = pio_inquire_variable(pioid, nvarid, vars(nvarid), ndims=ndims,dimids = dimids)
      if (rcode /= PIO_noerr) then
         write(s_logunit,*) subname//"ERROR inquiring about variable id #", nvarid
         call shr_sys_abort(subname//"ERROR inquiring about variable " )
      endif
      !-- If latitude variable ---
      if ( is_latlon( vars(nvarid), latitude=.true., varnotdim=.true. ) )then
         nlatdims = ndims
         allocate( latdimnames(ndims) )
         do ndimid =  1,ndims
            rcode = pio_inquire_dimension(pioid, dimids(ndimid), latdimnames(ndimid), len)
            if (rcode /= pio_noerr) then
               call shr_sys_abort(subname//"ERROR: Cant read netcdf latitude variable dimension")
            endif
            !--- is this a latitude dimension  ---
            if ( is_latlon( latdimnames(ndimid), latitude=.true., varnotdim=.false. ) )then
               latlen = len
            end if
         end do
      end if
      !-- If longitude variable ---
      if ( is_latlon( vars(nvarid), latitude=.false., varnotdim=.true. ) )then
         nlondims = ndims
         allocate( londimnames(ndims) )
         do ndimid =  1,ndims
            rcode = pio_inquire_dimension(pioid, dimids(ndimid), londimnames(ndimid), len)
            if (rcode /= PIO_noerr) then
               call shr_sys_abort(subname//"ERROR: Cant read netcdf latitude variable dimension")
            endif
            !--- is this a longitude dimension  ---
            if ( is_latlon( londimnames(ndimid), latitude=.false., varnotdim=.false. ) )then
               lonlen = len
            end if
         end do
      end if
   end do

   !--- Look for/extract lat lon coordinate variables from file ---

   nlat=0
   nlon=0
   nvarid=0

   !--- Loop through all variables until we find lat and lon ---

   do while (nvarid < nvars .and.(nlon.eq.0 .or. nlat.eq.0))
      nvarid=nvarid+1

      !--- Get latitude ---

      if ( is_latlon( vars(nvarid), latitude=.true., varnotdim=.true. ) )then

         call get_latlonindices( latitude=.true., ndims=nlatdims, dimnames=latdimnames, &
                                 nlen=latlen, strt=strt, count=count )
         nlat = latlen
         allocate(lats(nlat))
         rcode= pio_get_var(pioid, nvarid ,strt, count, lats)
         if (rcode /= PIO_noerr) then
            call shr_sys_abort( subname//"ERROR: Cant read netcdf latitude")
         endif
      end if

      !--- Get longitude ---

      if ( is_latlon( vars(nvarid), latitude=.false., varnotdim=.true. ) )then
         call get_latlonindices( latitude=.false., ndims=nlondims, dimnames=londimnames, &
                                 nlen=lonlen, strt=strt, count=count )
         nlon = lonlen
         allocate(lons(nlon))
         rcode= pio_get_var(pioid, nvarid ,strt, count, lons)
         if (rcode /= PIO_noerr) then
            call shr_sys_abort( subname//"ERROR: Cant read netcdf longitude")
         endif
      end if
   end do
   call pio_seterrorhandling(pioid,PIO_INTERNAL_ERROR)

   if ( present(found) )then
      if ( nlat == 0 .or. nlon == 0 ) then
         write(s_logunit,*) subname//"WARNING: Cant find appropriate latitude or longitude coordinate variables"
         found = .false.
      else
         call get_close( targetLon, targetLat, nlon, lons, nlat, lats, closelonidx, closelatidx, found )
         if ( found )then
            closelon=lons(closelonidx)
            closelat=lats(closelatidx)
         end if
      end if
   else
      call get_close( targetLon, targetLat, nlon, lons, nlat, lats, closelonidx, closelatidx )
      closelon=lons(closelonidx)
      closelat=lats(closelatidx)
   end if
   if ( allocated(lats) ) deallocate(lats)
   if ( allocated(lons) ) deallocate(lons)
   deallocate( vars )

   return
end subroutine shr_scam_getCloseLatLonPIO

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: shr_scam_getCloseLatLonFile
!
! !DESCRIPTION:
!    routine to search in netcdf file and return lat and lon point/index closest to target point
!
! !REVISION HISTORY:
!     2010 Oct 27 - E. Kluzek - first version
!
! !INTERFACE: ------------------------------------------------------------------

subroutine shr_scam_getCloseLatLonFile(filename, targetLat,  targetLon, closeLat, closeLon, &
                                       closeLatIdx, closeLonIdx)
! !USES:
   use shr_ncread_mod, only: shr_ncread_open, shr_ncread_close
   implicit none

! !INPUT/OUTPUT PARAMETERS:

   character(len=*),intent(in)    :: filename     ! Input NetCDF filename
   real   (R8),intent(in)         :: targetLat    ! find closest latitude to this point
   real   (R8),intent(in)         :: targetLon    ! find closest longitude to this point
   real   (R8),intent(out)        :: closeLat     ! returned close lat
   real   (R8),intent(out)        :: closeLon     ! returned close lon
   integer(IN),intent(out)        :: closeLatIdx  ! index of returned lat point
   integer(IN),intent(out)        :: closeLonIdx  ! index of returned lon point

!EOP


   !----- local variables -----
   integer :: ncid    ! NetCDF file ID
   integer :: rCode   ! return code
   character(*),parameter :: subname = "(shr_scam_getCloseLatLonFile) "

!-------------------------------------------------------------------------------
! Notes:
!-------------------------------------------------------------------------------
   call shr_ncread_open(fileName,ncid,rCode)
   call shr_scam_getCloseLatLonNC(ncid, targetLat,  targetLon, closeLat, closeLon, &
                                  closeLatIdx, closeLonIdx)
   call shr_ncread_close(ncid,rCode)

end subroutine shr_scam_getCloseLatLonFile


!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: shr_scam_checkSurface
!
! !DESCRIPTION:
!    routine to check grid fraction from the focndomain dataset
!    and provide information to correctly flag land, ocean or ice for
!    single column mode
!
! !REVISION HISTORY:
!     2007 Aug 29 - J. Truesdale - first version
!
! !INTERFACE: ------------------------------------------------------------------

subroutine shr_scam_checkSurface(scmlon, scmlat, ocn_compid, ocn_mpicom, lnd_present, ocn_present, ice_present)

! !USES:
   use shr_dmodel_mod    ! shr data model stuff
   use mct_mod
   use netcdf
   use shr_strdata_mod, only : shr_strdata_readnml, shr_strdata_type
   implicit none

! !INPUT/OUTPUT PARAMETERS:

   real(R8),                     intent(in)  :: scmlon,scmlat ! single column lat lon
   integer(IN),                  intent(in)  :: ocn_compid   ! id for ocean model  
   integer(IN),                  intent(in)  :: ocn_mpicom   ! mpi communicator for ocean  
   logical,            optional, intent(out) :: lnd_present  ! land point
   logical,            optional, intent(out) :: ice_present  ! ice point
   logical,            optional, intent(out) :: ocn_present  ! ocean point

!EOP

   !----- local variables -----
   type(shr_strdata_type)  :: SCAMSDAT
   integer(IN)             :: rcode            ! error code
   integer(IN)             :: ncid_ocn         ! netcdf id for ocn_in
   integer(IN)             :: fracid           !  id for frac variable
   integer(IN)             :: closeLatIdx      ! index of returned lat point
   integer(IN)             :: closeLonIdx      ! index of returned lon point
   integer(IN)             :: unitn            ! io unit
   real   (R8)             :: ocn_frac(1,1)    ! ocean fraction
   real   (R8)             :: closeLat         ! returned close lat
   real   (R8)             :: closeLon         ! returned close lon
   character(len=CL)       :: nrevsn = ' '     ! full path restart file for branch
   character(len=CL)       :: rest_pfile = './rpointer.dom' ! restart pointer file
   character(len=CL)       :: bndtvs           ! sst file
   character(len=CL)       :: focndomain       ! ocn domain file
   logical                 :: sstcyc           ! flag for sst cycling
   logical                 :: docn_exists           ! flag if file exists locally
   logical                 :: ocn_exists            ! flag if file exists locally
   logical                 :: exists            ! flag if file exists locally
   logical                 :: aqua_planet      ! flags
   logical                 :: single_column    ! flags

   !----- formats -----
   character(*),parameter :: subname = "(shr_scam_checkSurface) "
   character(*),parameter :: F00   = "('(shr_scam_checkSurface) ',8a)" 
   character(len=CL)      :: decomp = '1d' ! restart pointer file
   character(len=CL)      :: restfilm = 'unset' 
   character(len=CL)      :: restfils = 'unset'
   character(len=CL)      :: ocn_in = 'unset'
   integer(IN)   :: nfrac
   namelist /dom_inparm/ sstcyc, nrevsn, rest_pfile, bndtvs, focndomain
   namelist / docn_nml / ocn_in, decomp, restfilm, restfils

!-------------------------------------------------------------------------------
! Notes:
!-------------------------------------------------------------------------------

   inquire( file='ocn_in', exist=ocn_exists )
   inquire( file='docn_in', exist=docn_exists )
   if (ocn_exists) then
      !--- read in the ocn_in namelist to get name for focndomain file

      unitn = shr_file_getUnit() ! get an unused unit number
      open( unitn, file='ocn_in', status='old' )
      rcode = 1
      do while ( rcode /= 0 )
         read(unitn, dom_inparm, iostat=rcode)
         if (rcode < 0) then
            call shr_sys_abort( 'shr_scam_checkSurface encountered end-of-file on namelist read' )
         endif
      end do
      close( unitn )
      call shr_file_freeUnit(unitn)

      !--- open the netcdf file ---

      inquire(file=trim(focndomain),exist=exists)
      if (.not.exists) call shr_sys_abort(subName//"ERROR: file does not exist: "//trim(focndomain))
      rcode = nf90_open(focndomain,nf90_nowrite,ncid_ocn)
      if (rCode /= nf90_noerr) call shr_sys_abort(subName//"ERROR opening data file : "//trim(focndomain))
      if (s_loglev > 0) write(s_logunit,F00) 'opened netCDF data file: ',trim(focndomain)

      !--- Extract the fraction for current column ---
   
      call shr_scam_getCloseLatLon(ncid_ocn,scmlat,scmlon,closelat,closelon,closelatidx,closelonidx)
      rcode = nf90_inq_varid(ncid_ocn, 'frac', fracid)
      if (rcode /= nf90_noerr) then
         call shr_sys_abort(subname//"ERROR getting varid from variable frac in file "//trim(focndomain))
      end if
      rcode = nf90_get_var(ncid_ocn,fracid,ocn_frac,start=(/closelonidx,closelatidx/),count=(/1,1/))
      if (rcode /= nf90_noerr) then
         call shr_sys_abort(subname//"ERROR getting ocean fraction from "//trim(focndomain))
      end if

      !--- Set the appropriate surface flags based on ocean fraction.
   
      if ( present(ocn_present)      )                      ocn_present=(ocn_frac(1,1).gt.0.)
      if ( present(ocn_present).and.present(ice_present))   ice_present=ocn_present
      if ( present(lnd_present))                            lnd_present=(ocn_frac(1,1).lt.1.)
   else if (docn_exists) then
      !--- read in the ocn_in namelist to get name for focndomain file

      unitn = shr_file_getUnit() ! get an unused unit number
      open( unitn, file='docn_in', status='old' )
      rcode = 1
      do while ( rcode /= 0 )
         read (unitn,nml=docn_nml,iostat=rcode)
         if (rcode < 0) then
            call shr_sys_abort( 'shr_scam_checkSurface encountered end-of-file on namelist read' )
         endif
      end do
      close( unitn )
      call shr_file_freeUnit(unitn)
      call shr_strdata_readnml(SCAMSDAT,ocn_in)
      call shr_dmodel_readgrid(SCAMSDAT%grid,SCAMSDAT%gsmap,SCAMSDAT%nxg,SCAMSDAT%nyg, &
           SCAMSDAT%domainfile, ocn_compid, ocn_mpicom, '1d', readfrac=.true., &
           scmmode=.true.,scmlon=scmlon,scmlat=scmlat)
      nfrac = mct_aVect_indexRA(SCAMSDAT%grid%data,'frac')
      if ( present(ocn_present)      )                      ocn_present=(SCAMSDAT%grid%data%rAttr(nfrac,1).gt.0.)
      if ( present(ocn_present).and.present(ice_present))   ice_present=ocn_present
      if ( present(lnd_present))                            lnd_present=(SCAMSDAT%grid%data%rAttr(nfrac,1).lt.1.)
      call mct_ggrid_clean(SCAMSDAT%grid)
      call mct_gsmap_clean(SCAMSDAT%gsmap)
   else
   ! Exit early if no ocn component
      if ( present(ocn_present) ) ocn_present=.false.
      if ( present(ice_present) ) ice_present=.false.
      if ( present(lnd_present) ) lnd_present=.true.
   end if

end subroutine shr_scam_checkSurface

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: is_latlon
!
! !DESCRIPTION:
!
!     Returns true if the given variable name is a valid latitude or longitude
!     name. The logical input variable latitude is a flag to indicate if you are
!     checking for latitude or longitude variable names.
!
! !REVISION HISTORY:
!     2010 Oct 27 - E. Kluzek  - first version
!
! !INTERFACE: ------------------------------------------------------------------
logical function is_latlon( var_name, latitude, varnotdim )
! !USES:
! !INPUT/OUTPUT PARAMETERS:
    implicit none
    character(len=*), intent(in) :: var_name  ! Input variable name
    logical,          intent(in) :: latitude  ! Flag, true if you want a latitude variable
                                              ! if false check for longitude
    logical,          intent(in) :: varnotdim ! Flag, true if this is a variable 
                                              ! and NOT a dimension
!EOP

   !----- local variables -----
   character(len=3) :: xyvar    ! Variable name for 2D x-y coordinate variables
   character(len=3) :: Capxyvar ! change xyvar to caps
!-------------------------------------------------------------------------------
! Notes:
!-------------------------------------------------------------------------------

    is_latlon = .false.
    if ( latitude )then
      if ( varnotdim )then
         xyvar    = "xc"
         Capxyvar = "XC"
      else
         xyvar    = "nj"
         Capxyvar = "NJ"
      end if
      if ( trim(var_name) == 'lat'.or. trim(var_name) == 'latixy'.or.      &
           trim(var_name) == trim(xyvar) .or.trim(var_name) == 'lsmlat'.or.&
           trim(var_name) .eq. 'LAT'.or. trim(var_name) .eq. 'LATIXY'.or.  &
           trim(var_name) == trim(Capxyvar) .or. trim(var_name) .eq.'LSMLAT' )  then
           is_latlon = .true.
      else
           is_latlon = .false.
      end if
    else
      if ( varnotdim )then
         xyvar    = "yc"
         Capxyvar = "YC"
      else
         xyvar    = "ni"
         Capxyvar = "NI"
      end if
      if ( trim(var_name) == 'lon'.or. trim(var_name) == 'longxy'.or.      &
           trim(var_name) == trim(xyvar) .or.trim(var_name).eq.'lsmlon'.or.&
           trim(var_name) == 'LON'.or. trim(var_name) == 'LONGXY'.or.      &
           trim(var_name) == trim(Capxyvar) .or.trim(var_name).eq.'LSMLON' )  then
           is_latlon = .true.
      else
           is_latlon = .false.
      end if
    end if
    return
end function is_latlon

!===============================================================================

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: get_latlonindices
!
! !DESCRIPTION:
!        Get the start and count indices to retreive latitude or longitude
!
! !REVISION HISTORY:
!     2010 Nov 03 - E. Kluzek  - first version
!
! !INTERFACE: ------------------------------------------------------------------
subroutine get_latlonindices( latitude, ndims, dimnames, nlen, strt, count )
! !USES:
! !INPUT/OUTPUT PARAMETERS:
   implicit none
   logical,     intent(IN)  :: latitude            ! If this is latitude or not (long)
   integer(IN), intent(IN)  :: ndims               ! Number of dimensions
   character(len=*), intent(IN) :: dimnames(ndims) ! Dimension names
   integer(IN), intent(IN)  :: nlen                ! Dimension length
   integer(IN), intent(OUT) :: strt(ndims)         ! Start along dimension
   integer(IN), intent(OUT) :: count(ndims)        ! Count along dimension
!EOP

   !----- local variables -----
   integer(IN)   ::  ndimid
   logical       :: found = .false.
   character(*),parameter :: subname = "(shr_scam_getlatlonindices) "
!-------------------------------------------------------------------------------
! Notes:
!-------------------------------------------------------------------------------

   if ( ndims == 0 )then
      call shr_sys_abort( subname//"ERROR: Could NOT find dimension")
   end if
   if ( nlen  == 0 )then
      call shr_sys_abort( subname//"ERROR: Could NOT find dimension length")
   end if
   do ndimid =  1, ndims
      !--- is this a lat/longitude dimension  ---
      if ( is_latlon( dimnames(ndimid), latitude=latitude, varnotdim=.false. ) )then
         strt(ndimid)  = 1
         count(ndimid) = nlen
         found         = .true.
      else
         strt(ndimid)  = 1
         count(ndimid) = 1
      endif
   end do
   if (.not. found ) then
      if ( latitude )then
         call shr_sys_abort( subname//"ERROR: Cant find a useable latitude dimension" )
      else
         call shr_sys_abort( subname//"ERROR: Cant find a useable longitude dimension")
      end if
   end if
end subroutine get_latlonindices

!===============================================================================

!===============================================================================
!BOP ===========================================================================
!
! !IROUTINE: get_close
!
! !DESCRIPTION:
!           Get the close latitude and longitude indices for latitude/longitude.
!
! !REVISION HISTORY:
!     2010 Nov 03 - E. Kluzek  - first version
!
! !INTERFACE: ------------------------------------------------------------------
subroutine get_close( targetlon, targetlat, nlon, lons, nlat, lats, closelonidx, &
                      closelatidx, found )

! !USES:
! !INPUT/OUTPUT PARAMETERS:
   implicit none
   real   (R8),intent(in)   :: targetLon    ! find closest longitude to this point
   real   (R8),intent(in)   :: targetLat    ! find closest latitude to this point
   integer(IN),intent(in)   :: nlon         ! Number of longitudes
   real   (R8),intent(in)   :: lons(nlon)   ! Longitude array
   integer(IN),intent(in)   :: nlat         ! Number of latitudes
   real   (R8),intent(in)   :: lats(nlat)   ! Latitude array
   integer(IN),intent(out)  :: closeLatIdx  ! index of returned lat point
   integer(IN),intent(out)  :: closeLonIdx  ! index of returned lon point
   logical, optional, intent(out):: found   ! if found answer (will abort if found NOT sent and
                                            ! it couldn't find the lat/lon dimensions)
!EOP

   !----- local variables -----
   real   (R8),allocatable  :: poslons(:) 
   real   (R8)              :: postargetlon
   character(*),parameter :: subname = "(shr_scam_getclose) "
!-------------------------------------------------------------------------------
! Notes:
!-------------------------------------------------------------------------------
   if ( present(found) )then
      found = .true.
   end if

   !--- Did we get find valid lat and lon coordinate variables ---

   if (nlon == 0) then
      if ( present(found) )then
         found = .false.
         return
      else
         call shr_sys_abort( subname//"ERROR: Couldnt find a longitude coordinate variable")
      end if
   end if
   if (nlat == 0) then
      if ( present(found) )then
         found = .false.
         return
      else
         call shr_sys_abort( subname//"ERROR: Couldnt find a latitude coordinate variable")
      end if
   end if
   allocate(poslons(nlon))

   !--- convert lons array and targetlon to 0,360 ---

   poslons=mod(lons+360._r8,360._r8)
   postargetlon=mod(targetlon+360._r8,360._r8)

   !--- find index of value closest to 0 and set returned values ---

   closelonidx=(MINLOC(abs(poslons-postargetlon),dim=1))
   closelatidx=(MINLOC(abs(lats-targetlat),dim=1))

   !--- if it gets here we need to clean up after ourselves ---

   deallocate(poslons)
   return
end subroutine get_close

!===============================================================================

end module shr_scam_mod

