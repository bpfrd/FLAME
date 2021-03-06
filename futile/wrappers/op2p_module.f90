!> @file
!!  File to define information used for the overlap point to point between wavefunctions
!! @author
!!    Copyright (C) 2011-2016 BigDFT group
!!    This file is distributed under the terms of the
!!    GNU General Public License, see ~/COPYING file
!!    or http://www.gnu.org/copyleft/gpl.txt .
!!    For the list of contributors, see ~/AUTHORS


!> Modules which contains the defintions for overlap point to point
module overlap_point_to_point
   use f_enums
   use iso_c_binding
   use f_precisions
   implicit none

   !By default variables are internal to the module
   private

   integer, parameter :: LOCAL_=2,GLOBAL_=1
   integer, parameter :: SEND_DATA=1,RECV_DATA=2,SEND_RES=3,RECV_RES=4
   integer, parameter :: DATA_=1,RES_=2
   integer, parameter :: AFTER_=1,BEFORE_=2,NEXT_=3,PREVIOUS_=4

   integer, parameter :: wp=f_double !temporary substitution

   !> Used by the unitary test.
!!$   real(wp), parameter :: group_delta=2.0_wp,obj_delta=1.0_wp,elem_delta=1.e-6_wp
   real(wp) :: group_delta,obj_delta

   type(f_enumerator), parameter, public :: OP2P_START=f_enumerator('START',0,null())
   type(f_enumerator), parameter, public :: OP2P_CALCULATE=f_enumerator('CALCULATE',1,null())
   type(f_enumerator), parameter, public :: OP2P_EXIT=f_enumerator('EXIT',-1,null())

!!$   public :: initialize_OP2P_descriptors,OP2P_communication,OP2P_descriptors,free_OP2P_descriptors
   public :: local_data_init,set_local_data,free_local_data,OP2P_unitary_test,initialize_OP2P_data
   public :: set_OP2P_iterator,OP2P_communication_step,OP2P_info,free_OP2P_data,OP2P_test

!!$   type OP2P_descriptors
!!$      logical :: forsymop !< descriptor for symmetric operation
!!$      integer :: ngroup,nsteps_max,ngroupp_max,ncomponents_max,ncomponents_results_max,iprocref
!!$      integer, dimension(:), pointer :: ngroupp         !< number of groups which belongs to each processor
!!$      integer, dimension(:), pointer :: nprocgr         !< number of processors which belongs to each group
!!$      integer, dimension(:,:), pointer :: igrpr         !< groups which are associated to each processor
!!$      integer, dimension(:,:,:), pointer :: nvctr_par   !< number of elements per group, for objects and results
!!$      integer, dimension(:,:,:), pointer :: ioffp_group !< global and local offsets of each group on the processor
!!$      integer, dimension(:,:,:,:), pointer :: iprocpm1  !< ascending and descending order for processors in the same group
!!$      integer, dimension(:,:,:,:), pointer :: communication_schedule !< processes to send and receive at each step
!!$   end type OP2P_descriptors

   type, public :: OP2P_pointer
      real(wp), dimension(:,:), pointer :: ptr
      type(c_ptr):: ptr_gpu
   end type OP2P_pointer

   type, public :: local_data
      integer :: nobj !< number of objects to treat locally
      integer :: nvctr !<total number of elements of resident data
      integer :: nvctr_res !<total number of elements of processed resident data
      integer, dimension(:), pointer :: id_glb !<ids of the local data in the global distribution
      integer, dimension(:), pointer :: displ !<displacements of each of the local data
      integer, dimension(:), pointer :: displ_res !<displacements of each of the local results
      real(wp), dimension(:), pointer :: data !< array of local data
      real(wp), dimension(:), pointer :: res !< array of local results
      type(c_ptr) :: data_GPU !< array of local data on GPU
      type(c_ptr) :: res_GPU !< array of local results on GPU
   end type local_data

   !>structure exposing the local variable to be passed to the calculation routine
   type, public :: OP2P_iterator
      integer :: iproc !< process rank of the OP2P%mpi_comm communicator
      integer :: ncalls !<number of couples considered since now
      integer(f_long) :: initialisation_time !< initialisation time since the epoch
      logical :: remote_result !<the work array for the sending results has to be preparated
      integer :: istep !<step of the calculation
      integer :: igroup !<group being treated
      integer :: nloc_i,nloc_j !<number of local elements to  be treated
      integer :: isloc_i !<starting point of the elements for phi_i
      integer :: isloc_j !<starting point of the elements for phi_j
      type(local_data) :: phi_i !< local data associated to present processor
      type(local_data) :: phi_j !< local data of the present step, coming from separate processor
      type(f_enumerator) :: event !< OP2P event
   end type OP2P_iterator

   !> Type to control the communication scheduling
   type, public :: OP2P_data
      logical :: simulate !<toggle the simulation of the communication
      logical :: verbose !<verbosity of the communication
      logical :: nearest_neighbor !< communication patterns only involves close processes
      logical :: do_calculation !<tell is the calculation has to be done
      integer :: iproc_dump !<rank which dumps the communication
      integer :: istep !<actual step of the communication
      integer :: nstep !<maximum number of steps
      integer :: irecv_data !<position of the recv data in the work array
      integer :: isend_data !<position of the send data in the work array
      integer :: irecv_res !<position of the recv result in the work array
      integer :: isend_res !<position of the send result in the work array

      integer :: ndata_comms !<number of communication performed in the loop for the data
      integer :: nres_comms !<number of communication performed in the loop for the result
      integer :: igroup !<present group
      !> total number of groups
      integer :: ngroup
      integer :: ngroupp !<number of groups treated by the present process
      integer :: ndim !< size of the data per each object (can be generalized to an array)
      integer :: mpi_comm !<handle of the communicator
      integer :: gpudirect !<are we in a GPUDirect scenario? (cuda psolver + cuda-aware MPI) (should be removed from here, rather go in f_buffers)\
      integer :: tag_offset !<offset for the tags in the communications
      integer :: ncouples !<total number of couples considered
      !>stores the requests for the data
      integer, dimension(:), pointer :: requests_data
      !>stores the requests for the result
      integer, dimension(:), pointer :: requests_res
      !>data treated, to be used when simulating to
      !! see if the calculation is correct
      integer, dimension(:), pointer :: ndatac
      !>data sent, to be used when simulating to
      !! see if the communication is correct
      integer, dimension(:,:,:), pointer :: ndatas
      !> id of the group belonging to the local process
      integer, dimension(:), pointer :: group_id
      !>ranks of the processes interested to the communication in the given communicator
      integer, dimension(:,:,:), pointer :: ranks
      !>number of objects for each of the ranks and groups
      integer, dimension(:,:), pointer :: nobj_par
      !> id of the objects per rank and per group
      integer, dimension(:,:,:), pointer :: objects_id
      !> work arrays for the communication of the data
      type(OP2P_pointer), dimension(:,:), pointer :: dataw
      !> work arrays for the communication of the results, in the symmatric case
      type(OP2P_pointer), dimension(:,:), pointer :: resw
   end type OP2P_data


   contains


     !> Pure function
     function OP2P_iter_null() result(it)
       use wrapper_MPI
       use f_utils, only: f_zero
       implicit none
       type(OP2P_iterator) :: it
       it%iproc=mpirank_null()
       it%ncalls=0
       call f_zero(it%initialisation_time)
       it%remote_result=.false.
       it%igroup=0
       it%istep=-1
       it%nloc_i=-1
       it%nloc_j=-1
       it%isloc_i=0
       it%isloc_j=0
       call nullify_local_data(it%phi_i)
       call nullify_local_data(it%phi_j)
       it%event=OP2P_EXIT
     end function OP2P_iter_null


     subroutine nullify_local_data(ld)
       implicit none
       type(local_data), intent(out) :: ld
       ld%nobj=0
       ld%nvctr=0
       ld%nvctr_res=0
       nullify(ld%id_glb)
       nullify(ld%displ)
       nullify(ld%displ_res)
       nullify(ld%data)
       ld%data_GPU=C_NULL_PTR
       nullify(ld%res)
       ld%res_GPU=C_NULL_PTR
     end subroutine nullify_local_data

     !> type to control the communication scheduling
     pure subroutine nullify_OP2P_data(OP2P)
       use wrapper_MPI
       type(OP2P_data), intent(out) :: OP2P
        OP2P%simulate=.false.
        OP2P%verbose=.false.
        OP2P%do_calculation=.false. !<tell is the calculation has to be done
        OP2P%nearest_neighbor=.false. 
        OP2P%iproc_dump=mpirank_null()-1
        OP2P%istep=0
        OP2P%nstep=-1
        OP2P%irecv_data=2
        OP2P%isend_data=1
        OP2P%irecv_res=2
        OP2P%isend_res=1
        OP2P%ndata_comms=0
        OP2P%nres_comms=0
        OP2P%igroup=0
        OP2P%ngroup=-1
        OP2P%ngroupp=-1
        OP2P%ndim=0
        OP2P%mpi_comm=mpicomm_null() !<handle of the communicator
        OP2P%gpudirect=0
        OP2P%tag_offset=0
        OP2P%ncouples=0
        !then nullifications
        nullify(OP2P%requests_data)
        nullify(OP2P%requests_res)
        nullify(OP2P%ndatac)
        nullify(OP2P%ndatas)
        nullify(OP2P%group_id)
        nullify(OP2P%ranks)
        nullify(OP2P%nobj_par)
        nullify(OP2P%objects_id)
        nullify(OP2P%dataw)
        nullify(OP2P%resw)
      end subroutine nullify_OP2P_data

      subroutine free_OP2P_pointer(OP2P, ptr)
        use dynamic_memory
        implicit none
        type(OP2P_pointer), dimension(:,:), pointer :: ptr
        type(OP2P_data), intent(inout) :: OP2P
        !local variables
        integer :: i,j
        integer, dimension(2) :: lb,ub

        if (associated(ptr)) then
           lb=lbound(ptr)
           ub=ubound(ptr)
           do j=lb(2),ub(2)
              do i=lb(1),ub(1)
                if(OP2P%gpudirect /= 1) then
                  call f_free_ptr(ptr(i,j)%ptr)
                else
                  call cudafree(ptr(i,j)%ptr_gpu)
                end if
              end do
           end do
           deallocate(ptr)
           nullify(ptr)
        end if
      end subroutine free_OP2P_pointer

     function local_data_init(norb,ndim) result(ld)
       implicit none
       integer, intent(in) :: norb,ndim
       type(local_data) :: ld
       !local variables
       call nullify_local_data(ld)

       ld%nobj=norb
       ld%nvctr=ndim*norb
       ld%nvctr_res=ld%nvctr
     end function local_data_init

     subroutine set_local_data(ld,isorb,psir,dpsir,psir_gpu,dpsir_gpu)
       use dynamic_memory
       implicit none
       type(local_data), intent(inout) :: ld
       integer, intent(in) :: isorb
       real(wp), dimension(ld%nvctr), intent(in), target, optional :: psir
       real(wp), dimension(ld%nvctr_res), intent(in), target, optional :: dpsir
       type(c_ptr), optional :: psir_gpu
       type(c_ptr), optional :: dpsir_gpu
       !local variables
       integer :: iorb,ndim,ntot

       if (ld%nobj == 0) return

       ld%id_glb=f_malloc_ptr(ld%nobj,id='id_glb')
       ld%displ=f_malloc_ptr(ld%nobj,id='displ')
       ld%displ_res=f_malloc_ptr(ld%nobj,id='displ_res')

       ndim=ld%nvctr/ld%nobj
       do iorb=1,ld%nobj
          ld%id_glb(iorb)=iorb+isorb
       end do

       ntot=0
       do iorb=1,ld%nobj
          ld%displ(iorb)=ntot
          ld%displ_res(iorb)=ntot
          ntot=ntot+ndim
       end do

       !basic pointer association, no further allocation
       if (present(psir)) then
          ld%data=>psir
       else
          nullify(ld%data)
       end if
       if (present(dpsir)) then
          ld%res=>dpsir
       else
          nullify(ld%res)
       end if

        if (present(psir_gpu)) then
          ld%data_GPU=psir_gpu
       else
          ld%data_GPU=C_NULL_PTR
       end if
       if (present(dpsir_gpu)) then
          ld%res_GPU=dpsir_gpu
       else
          ld%res_GPU=C_NULL_PTR
       end if
     end subroutine set_local_data

     subroutine free_local_data(ld)
       use dynamic_memory
       implicit none
       type(local_data), intent(inout) :: ld

       call f_free_ptr(ld%id_glb)
       call f_free_ptr(ld%displ)
       call f_free_ptr(ld%displ_res)
       call nullify_local_data(ld)

     end subroutine free_local_data

     subroutine cuda_estimate_memory_needs_gpudirect(iproc, nproc, OP2P, symmetric)
       use iso_c_binding
       use yaml_output
       use wrapper_MPI
       implicit none
       integer(kind=C_SIZE_T) :: freeGPUSize, totalGPUSize, gpudirectresSize,gpudirectdataSize,phimemSize
       logical, intent(inout) :: symmetric
       integer, intent(in) :: iproc, nproc
       integer :: i, igroup, iproc_node, nproc_node
       type(OP2P_data), intent(inout) :: OP2P
       real(wp) alpha
       logical ltmp
       freeGPUSize=0
       totalGPUSize=0
       gpudirectdataSize=0
       gpudirectresSize=0
       phimemSize=0

       call cuda_get_mem_info(freeGPUSize,totalGPUSize)
       call mpinoderanks(iproc,nproc,OP2P%mpi_comm,iproc_node,nproc_node)
       !call processor_id_per_node(iproc,nproc,iproc_node,nproc_node)
       
       do i=1,2
         do igroup=1,OP2P%ngroupp
           gpudirectdataSize=gpudirectdataSize+OP2P%ndim*maxval(OP2P%nobj_par(:,OP2P%group_id(igroup)))*f_sizeof(alpha)
          end do
       end do

       do i=1,3
         do igroup=1,OP2P%ngroupp
           if (symmetric) then
             gpudirectresSize=gpudirectresSize+OP2P%ndim*maxval(OP2P%nobj_par(:,OP2P%group_id(igroup)))*f_sizeof(alpha)
           end if
         end do
       end do

       phimemSize=OP2P%ndim*sum(OP2P%nobj_par(iproc,:))*2*sizeof(alpha)

       if((nproc_node * (phimemSize+gpudirectdataSize+gpudirectresSize) )< freeGPUSize) then
         OP2P%gpudirect=1
       else if ((nproc_node * (phimemSize+gpudirectdataSize))<freeGPUSize) then

         symmetric = .false.
         OP2P%gpudirect=1
       else
         OP2P%gpudirect=0
       end if
    !  end if

    ! gpudirect is an integer, and some implementations of MPI don't provide MPI_LAND for integers
    ltmp=OP2P%gpudirect==1
    call mpiallred(ltmp,1,MPI_LAND)
    OP2P%gpudirect= merge(1,0,ltmp)
    call mpiallred(symmetric,1,MPI_LAND)

    if (OP2P%gpudirect==0 .and. iproc==0) then
         call yaml_warning("insufficient GPU memory : using non gpudirect version ")
    else if ((symmetric .eqv. .false.) .and. iproc==0 .and. nproc > 1) then
         call yaml_warning("insufficient GPU memory : don't store and exchange results"//&
              " (double the computation amount)")
    end if

     end subroutine cuda_estimate_memory_needs_gpudirect

     subroutine initialize_OP2P_data(OP2P,mpi_comm,iproc,nproc,ngroup,ndim,nobj_par,igpu,&
          symmetric,nearest_neighbor,tag_offset)
       use dynamic_memory
       use wrapper_MPI
       use yaml_strings
       use dictionaries, only: f_err_throw
       implicit none
       !>flag indicating the symmetricity of the operation. This reflects in the communication scheduling
       logical, intent(inout) :: symmetric
       integer, intent(in) :: mpi_comm,iproc,nproc,ngroup,ndim,igpu
       integer, dimension(0:nproc-1,ngroup), intent(in) :: nobj_par
       type(OP2P_data), intent(out) :: OP2P
       logical, intent(in), optional :: nearest_neighbor
       integer, intent(in), optional :: tag_offset

       !local variables
       logical :: nn
       integer :: igroup,icount,icountmax,iprocgrs,iprocgrr,jproc,igr,nobjp,nprocgr
       integer :: istep,nsteps,isobj,iobj_local,i,i_stat,maxtag
       integer, dimension(:,:,:), allocatable :: iprocpm1

       call nullify_OP2P_data(OP2P)

       nn=.false.
       if (present(nearest_neighbor)) nn=nearest_neighbor

       if (present(tag_offset)) OP2P%tag_offset=tag_offset

       OP2P%ngroup=ngroup
       OP2P%ndim=ndim
       OP2P%mpi_comm=mpi_comm
       OP2P%nearest_neighbor=nn

       !check if the maximum tag would create problems
       maxtag=nproc
       if (symmetric) maxtag=maxtag+nproc
       if (maxtag > mpimaxtag(OP2P%mpi_comm)) then
          call f_err_throw('Maximal tag "'+maxtag+'" is outside the allowed range',&
               err_name='BIGDFT_RUNTIME_ERROR')
       end if

       OP2P%nobj_par=f_malloc_ptr([0.to.nproc-1,1.to.ngroup],id='nobj_par')
       call f_memcpy(src=nobj_par,dest=OP2P%nobj_par)

       !here we can allocate the working arrays giving the maximum
       !between the components for each group
       OP2P%ngroupp=0
       do igroup=1,OP2P%ngroup
          if (OP2P%nobj_par(iproc,igroup) > 0) then
             OP2P%ngroupp=OP2P%ngroupp+1
          end if
       end do

       OP2P%requests_data=f_malloc_ptr(2*OP2P%ngroupp,id='requests_data')
       OP2P%requests_res= f_malloc_ptr(2*OP2P%ngroupp,id='requests_res')

       OP2P%objects_id = f_malloc_ptr((/ 1.to.2, 0.to.nproc-1, 1.to.OP2P%ngroup /),id='objects_id')

       isobj=0
       do jproc=0,nproc-1
          iobj_local=1
          do igroup=1,OP2P%ngroup
             OP2P%objects_id(GLOBAL_,jproc,igroup)=isobj+iobj_local-1
             OP2P%objects_id(LOCAL_,jproc,igroup)=iobj_local
             iobj_local=iobj_local+OP2P%nobj_par(jproc,igroup)
          end do
          isobj=isobj+iobj_local-1
       end do

       !determine the array of the groups which are of interest for this processor
       OP2P%group_id = f_malloc_ptr(OP2P%ngroupp,id='group_id')
       !determine for each processor the groups which has to be used
       icount=0
       do igroup=1,ngroup
          if (OP2P%nobj_par(iproc,igroup) > 0) then
             icount=icount+1
             OP2P%group_id(icount)=igroup
          end if
       end do

       !find the processor which has the maximum number of groups
       icountmax=0
       do jproc=0,nproc-1
          icount=count(OP2P%nobj_par(jproc,:) > 0)
          if (icount > icountmax) then
             OP2P%iproc_dump=jproc
             icountmax=icount
          end if
       end do

       if(igpu/=0) call cuda_estimate_memory_needs_gpudirect(iproc, nproc, OP2P, symmetric)

       !decide the strategy for the communication
       if (symmetric) then
          OP2P%nstep=(nproc-1)/2+1!nproc/2+1
       else
          OP2P%nstep=nproc-1
       end if

       iprocpm1 = f_malloc((/ 1.to.2, 0.to.nproc-1, 1.to.OP2P%ngroupp /),id='iprocpm1')
       !calculate the processor which lies after and before the present in the list
       iprocpm1=mpirank_null()

       !test array for data calculation
       OP2P%ndatac = f_malloc0_ptr(OP2P%ngroupp,id='ndatac')

       do igroup=1,OP2P%ngroupp
          igr=OP2P%group_id(igroup)
          iprocgrs=-1
          iprocgrr=-1

          !define the number of data to calculate in total
          do jproc=0,nproc-1
             OP2P%ndatac(igroup)=OP2P%ndatac(igroup)-OP2P%ndim*OP2P%nobj_par(jproc,igr)
             if (OP2P%nobj_par(modulo(iproc+jproc,nproc),igr) > 0 .and. .true.) then
                iprocgrs=iprocgrs+1
                iprocpm1(AFTER_,iprocgrs,igroup)=modulo(iproc+jproc,nproc)
             end if
             if (OP2P%nobj_par(modulo(iproc-jproc,nproc),igr) > 0 .and. .true.) then
                iprocgrr=iprocgrr+1
                iprocpm1(BEFORE_,iprocgrr,igroup)=modulo(iproc-jproc,nproc)
             end if
          end do
       end do

       !calculate the list of send-receive operations which have to be performed per group
       !allocate it at the maximum size needed
       OP2P%ranks = f_malloc_ptr([1.to.4, 1.to.OP2P%ngroupp, 0.to.OP2P%nstep],id='ranks')
       !initalise array to rank_null
       OP2P%ranks=mpirank_null()

       OP2P%ncouples=0
       do igroup=1,OP2P%ngroupp
          igr=OP2P%group_id(igroup)
          nobjp=OP2P%nobj_par(iproc,igr)
          OP2P%ncouples=OP2P%ncouples+(nobjp*(nobjp+1))/2
          !calculate the number of processors per group
          nprocgr=count(OP2P%nobj_par(:,igr)>0)
          !do not send anything if there is only one member
          if (nprocgr > 1) then
             if (symmetric) then
                nsteps=(nprocgr-1)/2
             else
                nsteps=nprocgr-1
             end if
             do istep=0,nsteps-1
                !define the arrays for send-receive of data
                OP2P%ranks(SEND_DATA,igroup,istep)= iprocpm1(AFTER_,istep+1,igroup)
                OP2P%ranks(RECV_DATA,igroup,istep)= iprocpm1(BEFORE_,istep+1,igroup)
                if (OP2P%ranks(RECV_DATA,igroup,istep) /= mpirank_null()) then
                   OP2P%ncouples=OP2P%ncouples+&
                        OP2P%nobj_par(OP2P%ranks(RECV_DATA,igroup,istep),igr)*OP2P%nobj_par(iproc,igr)
                end if
                if (istep > 0 .and. symmetric) then
                   OP2P%ranks(SEND_RES,igroup,istep)=iprocpm1(BEFORE_,istep,igroup)
                   OP2P%ranks(RECV_RES,igroup,istep)=iprocpm1(AFTER_,istep,igroup)
                end if
             end do
             !last case
             istep=nsteps!(nprocgr-1)/2
             !the last step behaves differently if the number of members is odd or even
             if ((modulo(nprocgr,2) == 0 .or. .not. symmetric) .and. istep+1 <= nproc-1) then
                OP2P%ranks(SEND_DATA,igroup,istep)= iprocpm1(AFTER_,istep+1,igroup)
                OP2P%ranks(RECV_DATA,igroup,istep)= iprocpm1(BEFORE_,istep+1,igroup)
                if (OP2P%ranks(RECV_DATA,igroup,istep) /= mpirank_null()) then
                   OP2P%ncouples=OP2P%ncouples+&
                        OP2P%nobj_par(OP2P%ranks(RECV_DATA,igroup,istep),igr)*OP2P%nobj_par(iproc,igr)
                end if
                if (istep > 0 .and. symmetric) then
                   OP2P%ranks(SEND_RES,igroup,istep)=iprocpm1(BEFORE_,istep,igroup)
                   OP2P%ranks(RECV_RES,igroup,istep)=iprocpm1(AFTER_,istep,igroup)
                end if
             else if (symmetric) then
                OP2P%ranks(SEND_RES,igroup,istep)=iprocpm1(BEFORE_,istep,igroup)
                OP2P%ranks(RECV_RES,igroup,istep)=iprocpm1(AFTER_,istep,igroup)
             end if
          end if
       end do
       call f_free(iprocpm1)

       !real communication
       OP2P%iproc_dump=mpirank_null()-1! =no debug verbosity


       allocate(OP2P%dataw(OP2P%ngroupp,2))
       do i=1,2
          do igroup=1,OP2P%ngroupp
            if(OP2P%gpudirect/=1) then
              OP2P%dataw(igroup,i)%ptr=&
                  f_malloc_ptr([OP2P%ndim, maxval(OP2P%nobj_par(:,OP2P%group_id(igroup)))],&
                  id='dataw'+yaml_toa(igroup)+yaml_toa(i))
            else
              call  cudamalloc(OP2P%ndim*maxval(OP2P%nobj_par(:,OP2P%group_id(igroup))),&
                                OP2P%dataw(igroup,i)%ptr_gpu,i_stat)
              if (i_stat /= 0) print *,'error cudamalloc dataw GPU',i_stat
            end if
          end do
       end do

       allocate(OP2P%resw(OP2P%ngroupp,3))
       do i=1,3
          do igroup=1,OP2P%ngroupp
             if (symmetric) then
               if(OP2P%gpudirect/=1) then
                 OP2P%resw(igroup,i)%ptr=&
                     f_malloc_ptr([OP2P%ndim, maxval(OP2P%nobj_par(:,OP2P%group_id(igroup)))],&
                     id='resw'+yaml_toa(igroup)+yaml_toa(i))
                else
                  call cudamalloc(OP2P%ndim* maxval(OP2P%nobj_par(:,OP2P%group_id(igroup))),&
                                  OP2P%resw(igroup,i)%ptr_gpu,i_stat)
                  if (i_stat /= 0) print *,'error cudamalloc resw GPU',i_stat
                end if
             else
               if(OP2P%gpudirect/=1) then
                  nullify(OP2P%resw(igroup,i)%ptr)
                else
                 OP2P%resw(igroup,i)%ptr_gpu=C_NULL_PTR
                end if
             end if
          end do
       end do

       !test array for data sending
       OP2P%ndatas = f_malloc0_ptr([1.to.2, 0.to.nproc-1, 1.to.OP2P%ngroup],id='ndatas')

     end subroutine initialize_OP2P_data

     !> type to control the communication scheduling
     subroutine free_OP2P_data(OP2P)
       use wrapper_MPI
       use dictionaries, only: f_err_throw
       use yaml_strings
       use dynamic_memory
       implicit none
       type(OP2P_data), intent(inout) :: OP2P
       !local variables
       integer :: iproc

       iproc=mpirank(OP2P%mpi_comm)
       if (any(OP2P%ndatac /=0)) then
          call f_err_throw('ERROR: OP2P communication simulation failed: processor '&
               +yaml_toa(iproc)+&
               ' has calculated'+ yaml_toa(OP2P%ndatac)+&
               ' data more than needed',err_name='BIGDFT_RUNTIME_ERROR')
       end if

       !check the total amount of communication and calculations
       if (mpisize(OP2P%mpi_comm) > 1) &
            call mpiallred(OP2P%ndatas,MPI_SUM,comm=OP2P%mpi_comm)
       if (any(OP2P%ndatas(:,iproc,OP2P%group_id) /=0)) then
          call f_err_throw('ERROR: OP2P communication simulation failed: processor '+yaml_toa(iproc)+&
               ' has not a zero balance of send-receive calls'+&
               yaml_toa(reshape(OP2P%ndatas(:,iproc,OP2P%group_id),&
               [2*OP2P%ngroupp])),&
               err_name='BIGDFT_RUNTIME_ERROR')
          stop
       end if

       !then nullifications
       call f_free_ptr(OP2P%requests_res)
       call f_free_ptr(OP2P%requests_data)
       call f_free_ptr(OP2P%ndatac)
       call f_free_ptr(OP2P%ndatas)
       call f_free_ptr(OP2P%group_id)
       call f_free_ptr(OP2P%ranks)
       call f_free_ptr(OP2P%nobj_par)
       call f_free_ptr(OP2P%objects_id)
       call free_OP2P_pointer(OP2P,OP2P%dataw)
       call free_OP2P_pointer(OP2P,OP2P%resw)
       call nullify_OP2P_data(OP2P)
     end subroutine free_OP2P_data


     !> Create an iterator iter from OP2P object.
     subroutine set_OP2P_iterator(iproc,OP2P,iter,norbp,data,res)
       use f_utils
       implicit none
       integer, intent(in) :: norbp,iproc
       type(OP2P_data), intent(in) :: OP2P
       type(OP2P_iterator), intent(out) :: iter
       !todo: make res optional if the loop does not need it
       real(wp), dimension(OP2P%ndim*norbp), intent(in), target :: data,res
       integer i_stat

       iter=OP2P_iter_null()
       !then create the local data object
       iter%phi_i=local_data_init(norbp,OP2P%ndim)
       if (OP2P%ngroupp>0) then
          call set_local_data(iter%phi_i,OP2P%objects_id(GLOBAL_,iproc,OP2P%group_id(1)))
       end if
       !basic pointer association, no further allocation

         iter%phi_i%data=>data
         iter%phi_i%res=>res
       if(OP2P%gpudirect==1) then

         ! initialize GPU arrays that will hold the data for all the computation
         call cudamalloc(OP2P%ndim*norbp,iter%phi_i%data_GPU, i_stat)
         if (i_stat /= 0) print *,'error cudamalloc data_GPU',i_stat
         call reset_gpu_data(OP2P%ndim*norbp,data,iter%phi_i%data_GPU)

         call cudamalloc(OP2P%ndim*norbp,iter%phi_i%res_GPU,i_stat)
         if (i_stat /= 0) print *,'error cudamalloc res_GPU',i_stat
         !is this necessary?
         !call cudamemset(iter%phi_i%res_GPU, 0, OP2P%ndim*norbp,i_stat)
         call reset_gpu_data(OP2P%ndim*norbp,res,iter%phi_i%res_GPU)
         !if (i_stat /= 0) print *,'error cudamemset phi_i%res_GPU',i_stat

       end if

       !example of the usage of the loop
       iter%event=OP2P_START
       iter%iproc=iproc
       iter%initialisation_time=f_time()
     end subroutine set_OP2P_iterator

     subroutine release_OP2P_iterator(iter)
       implicit none
       type(OP2P_iterator), intent(inout) :: iter
       !free the loop variables
       call free_local_data(iter%phi_i)
       !here release the iterator
       iter=OP2P_iter_null()
     end subroutine release_OP2P_iterator


     !> define tag according to the strategy
     !pure 
     function OP2P_tag(OP2P,iproc,back) result(tag)
       use wrapper_MPI, only: mpisize
       implicit none
       type(OP2P_data), intent(in) :: OP2P 
       integer, intent(in) :: iproc
       logical, intent(in), optional :: back
       integer :: tag

       tag=iproc
       if (present(back)) then
          if (back) tag=tag+mpisize(OP2P%mpi_comm)
       end if
       tag=tag+OP2P%tag_offset
       
     end function OP2P_tag

     !>get the rank to which we have to send the data
     !pure 
     function get_send_rank(igroup,OP2P)
       use wrapper_MPI
       implicit none
       integer, intent(in) :: igroup
       type(OP2P_data), intent(in) :: OP2P
       integer :: get_send_rank
       if (OP2P%nearest_neighbor) then
          !however send data only if the next process was supposed to receive them
          !this only works when step and processes can be interchanged
          !therefore without holes
          if (OP2P%istep==OP2P%nstep) then
             get_send_rank=mpirank_null()
          else if (OP2P%istep==0 .or. &
               OP2P%ranks(SEND_DATA,igroup,OP2P%istep) /= mpirank_null()) then
             get_send_rank=OP2P%ranks(SEND_DATA,igroup,0)
          else
             get_send_rank=mpirank_null()
          end if
       else
          get_send_rank=OP2P%ranks(SEND_DATA,igroup,OP2P%istep)
       end if

       !print *,'here',get_send_rank,mpirank(),OP2P%istep,OP2P%nstep
     end function get_send_rank

     !>get the rank to which we have to recv the data
     pure function get_recv_rank(igroup,OP2P)
       use wrapper_MPI
       implicit none
       integer, intent(in) :: igroup
       type(OP2P_data), intent(in) :: OP2P
       integer :: get_recv_rank
       get_recv_rank=OP2P%ranks(RECV_DATA,igroup,OP2P%istep)
       if (OP2P%nearest_neighbor .and. get_recv_rank /= mpirank_null())&
            get_recv_rank=OP2P%ranks(RECV_DATA,igroup,0)

     end function get_recv_rank

     !>get the original processor of the data we are treating
     pure function get_sendbuf_provenance(iproc,igroup,OP2P)
       use wrapper_MPI
       implicit none
       integer, intent(in) :: iproc,igroup
       type(OP2P_data), intent(in) :: OP2P
       integer :: get_sendbuf_provenance
       if (OP2P%nearest_neighbor .and. OP2P%istep > 0) then
          get_sendbuf_provenance=OP2P%ranks(RECV_DATA,igroup,OP2P%istep-1)
       else
          get_sendbuf_provenance=iproc !scheme of general pattern
       end if
     end function get_sendbuf_provenance

     !>get the original processor of the data we are treating
     pure function get_recvbuf_provenance(iproc,OP2P)
       use wrapper_MPI
       implicit none
       integer, intent(in) :: iproc
       type(OP2P_data), intent(in) :: OP2P
       integer :: get_recvbuf_provenance

       if (OP2P%istep == 0) then
          get_recvbuf_provenance=iproc
       else
          get_recvbuf_provenance=OP2P%ranks(RECV_DATA,OP2P%igroup,OP2P%istep-1) !scheme of general pattern
       end if
     end function get_recvbuf_provenance

     !>return the send buffer associated to the chosen parallelisation
     !!scheme
     function sendbuf(iproc,igroup,OP2P,phi,nelems,jshift)
       use dynamic_memory
       implicit none
       integer, intent(in) :: iproc,igroup
       type(OP2P_data), intent(in) :: OP2P
       type(local_data), intent(in) :: phi
       integer, intent(out) :: nelems,jshift
       real(f_double), dimension(:), pointer :: sendbuf !this will become f_buffer
       !local variables
       integer :: original_source,igr,iobj_local

       igr=OP2P%group_id(igroup)
       original_source=get_sendbuf_provenance(iproc,igroup,OP2P)
       nelems=OP2P%nobj_par(original_source,igr)*OP2P%ndim
       iobj_local=OP2P%objects_id(LOCAL_,original_source,igr)
       jshift=phi%displ(iobj_local)
 
       nullify(sendbuf)
       !this is the alternative communication scheme
       if (OP2P%istep == 0 .or. .not. OP2P%nearest_neighbor) then
          !we send the local data
          sendbuf => f_subptr(phi%data,from=1+jshift,size=nelems)
          !sendbuf => phi%data(1+jshift:nelems+jshift)
       else
          !in this scheme we send the data we retrieved at the previous step
          sendbuf => remap_ptr_tmp(OP2P%dataw(igroup,OP2P%isend_data)%ptr,&
               size(OP2P%dataw(igroup,OP2P%isend_data)%ptr))
       end if

     end function sendbuf

     function remap_ptr_tmp(ptr,n) result(tmp)
       implicit none
       integer, intent(in) :: n
       real(f_double), dimension(n), intent(in), target :: ptr
       real(f_double), dimension(:), pointer :: tmp

       tmp => ptr
     end function remap_ptr_tmp

     subroutine P2P_data(iproc,OP2P,phi)!,psiw)
       use wrapper_MPI
       implicit none
       integer, intent(in) :: iproc

       type(OP2P_data), intent(inout) :: OP2P
 !      real(wp), dimension(OP2P%ndim,norbp), intent(in) :: psir
       type(local_data), intent(inout) :: phi
       !local variables
       integer :: igroup,dest,source,count,igr,jshift
       integer :: norbp!,original_source,norbp_max,iobj_local
       real(f_double), dimension(:), pointer :: tmp

       norbp=phi%nobj
       !sending receiving data
       do igroup=1,OP2P%ngroupp
          igr=OP2P%group_id(igroup)
          dest=get_send_rank(igroup,OP2P)!OP2P%ranks(SEND_DATA,igroup,OP2P%istep)
          if (dest /= mpirank_null()) then
!!$             original_source=get_sendbuf_provenance(iproc,igroup,OP2P)
!!$             count=OP2P%nobj_par(original_source,igr)*OP2P%ndim
!!$             iobj_local=OP2P%objects_id(LOCAL_,original_source,igr)
!!$             jshift=phi%displ(iobj_local)

             tmp => sendbuf(iproc,igroup,OP2P,phi,count,jshift)

             OP2P%ndata_comms=OP2P%ndata_comms+1
             !send the fixed array to the processor which comes in the list
             OP2P%ndatas(DATA_,dest,igr)=&
                  OP2P%ndatas(DATA_,dest,igr)+count
             if(OP2P%gpudirect/=1)then
                call mpisend(tmp(1),count,&
                     dest=dest,tag=OP2P_tag(OP2P,iproc),comm=OP2P%mpi_comm,&
                     request=OP2P%requests_data(OP2P%ndata_comms),&
                     verbose=OP2P%verbose,simulate=OP2P%simulate) ! dest==OP2P
!!$               call mpisend(phi%data(1+jshift),count,&
!!$                  dest=dest,tag=iproc,comm=OP2P%mpi_comm,&
!!$                  request=OP2P%requests_data(OP2P%ndata_comms),&
!!$                  verbose=OP2P%verbose,simulate=OP2P%simulate) ! dest==OP2P%iproc_dump
             else
               call mpisend(phi%data_GPU,count,&
                  dest=dest,tag=OP2P_tag(OP2P,iproc),comm=OP2P%mpi_comm,&
                  request=OP2P%requests_data(OP2P%ndata_comms),&
                  verbose=OP2P%verbose,simulate=OP2P%simulate,&
                  type=MPI_DOUBLE_PRECISION,offset=jshift) ! dest==OP2P%iproc_dump
             end if
          end if

          source=get_recv_rank(igroup,OP2P)!OP2P%ranks(RECV_DATA,igroup,OP2P%istep)
          if (source /= mpirank_null()) then
             !count=OP2P%ndim*OP2P%nobj_par(source,igr)
             count=OP2P%ndim*OP2P%nobj_par(OP2P%ranks(RECV_DATA,igroup,OP2P%istep),igr)
             OP2P%ndata_comms=OP2P%ndata_comms+1
             OP2P%ndatas(DATA_,iproc,igr)=&
                  OP2P%ndatas(DATA_,iproc,igr)-count
             if(OP2P%gpudirect/=1)then
               call mpirecv(OP2P%dataw(igroup,OP2P%irecv_data)%ptr(1,1),count,&!psiw(1,1,igroup,OP2P%irecv_data),count,&
                  source=source,tag=OP2P_tag(OP2P,source),comm=OP2P%mpi_comm,&
                  request=OP2P%requests_data(OP2P%ndata_comms),&
                  verbose=OP2P%verbose,simulate=OP2P%simulate) ! source == OP2P%iproc_dump
            else
               call mpirecv(OP2P%dataw(igroup,OP2P%irecv_data)%ptr_gpu,count,&!psiw(1,1,igroup,OP2P%irecv_data),count,&
                  source=source,tag=OP2P_tag(OP2P,source),comm=OP2P%mpi_comm,&
                  request=OP2P%requests_data(OP2P%ndata_comms),&
                  verbose=OP2P%verbose,simulate=OP2P%simulate,&
                  type=MPI_DOUBLE_PRECISION) ! source == OP2P%iproc_dump
            end if
          end if
       end do

     end subroutine P2P_data

     subroutine P2P_res(iproc,OP2P,phi)!,dpsiw)
       use wrapper_MPI
       use dynamic_memory
       use wrapper_linalg
       implicit none
       integer, intent(in) :: iproc
       type(OP2P_data), intent(inout) :: OP2P
       type(local_data), intent(inout) :: phi
       integer :: norbp!,norbp_max
      ! real(wp), dimension(OP2P%ndim,norbp) :: dpsir

       !real(wp), dimension(OP2P%ndim,norbp_max,OP2P%ngroup,3), intent(inout) :: dpsiw
       !local variables
       integer :: igroup,dest,source,count,igr,jshift


       norbp = phi%nobj
       !nproc=mpisize(OP2P%mpi_comm)
       if (OP2P%nres_comms > 0) then
          !verify that the messages have been passed
          call mpiwaitall(OP2P%nres_comms,OP2P%requests_res,&
               simulate=OP2P%simulate)
          !copy the results which have been received (the messages sending are after)
          !this part is already done by the mpi_accumulate
          do igroup=1,OP2P%ngroupp
             source=OP2P%ranks(RECV_RES,igroup,OP2P%istep-1)
             igr=OP2P%group_id(igroup)
             jshift=phi%displ(OP2P%objects_id(LOCAL_,iproc,igr))
             if (source /= mpirank_null()) then
                if (OP2P%verbose) then
                   print '(5(1x,a,i8))','step',OP2P%istep,'group:',igr,&
                        ':copying',OP2P%ndim*OP2P%nobj_par(iproc,igr),&
                        'processed elements from',source,'in',iproc
                end if
                OP2P%ndatac(igroup)=OP2P%ndatac(igroup)+&
                     OP2P%ndim*OP2P%nobj_par(source,igr)
                if(OP2P%gpudirect/=1) then
                  call axpy(OP2P%ndim*OP2P%nobj_par(iproc,igr),1.0_wp,OP2P%resw(igroup,OP2P%irecv_res)%ptr(1,1),1,&
                     phi%res(1+jshift),1)
                else

!void CUBLAS_DAXPY (const int *n, const double *alpha, const devptr_t *devPtrx,
!                   const int *incx, const devptr_t *devPtry, const int *incy)
                   call poisson_cublas_daxpy(OP2P%ndim*OP2P%nobj_par(iproc,igr),1.0_wp,OP2P%resw(igroup,OP2P%irecv_res)%ptr_gpu,1,&
                     !dpsiw(1,1,igroup,OP2P%irecv_res),1,&
                   phi%res_GPU,1,jshift)
                end if
             end if
          end do
       end if

       OP2P%nres_comms=0
       !meanwhile, we can receive the result from the processor which has the psi
       OP2P%irecv_res=3-OP2P%isend_res
       do igroup=1,OP2P%ngroupp
          igr=OP2P%group_id(igroup)
          dest=OP2P%ranks(SEND_RES,igroup,OP2P%istep)
          if (dest /= mpirank_null()) then
             OP2P%nres_comms=OP2P%nres_comms+1
             count=OP2P%ndim*OP2P%nobj_par(dest,igr)
             !here we can swap pointers
             if(OP2P%gpudirect/=1)then
               call f_memcpy(src=OP2P%resw(igroup,3)%ptr,&
                  dest=OP2P%resw(igroup,OP2P%isend_res)%ptr)
               call mpisend(OP2P%resw(igroup,OP2P%isend_res)%ptr(1,1),&!dpsiw(1,1,igroup,OP2P%isend_res),&
                  count,dest=dest,&
                  tag=OP2P_tag(OP2P,iproc,back=.true.),comm=OP2P%mpi_comm,&
                  request=OP2P%requests_res(OP2P%nres_comms),simulate=OP2P%simulate,verbose=OP2P%verbose)
              else
               call copy_gpu_data(OP2P%ndim* maxval(OP2P%nobj_par(:,OP2P%group_id(igroup))),&
                    OP2P%resw(igroup,OP2P%isend_res)%ptr_gpu,OP2P%resw(igroup,3)%ptr_gpu)
               call synchronize()
               call mpisend(OP2P%resw(igroup,OP2P%isend_res)%ptr_gpu,&!dpsiw(1,1,igroup,OP2P%isend_res),&
                  count,dest=dest,&
                  tag=OP2P_tag(OP2P,iproc,back=.true.),comm=OP2P%mpi_comm,&
                  request=OP2P%requests_res(OP2P%nres_comms),simulate=OP2P%simulate,verbose=OP2P%verbose,&
                  type=MPI_DOUBLE_PRECISION)
              end if
             OP2P%ndatas(RES_,dest,igr)=OP2P%ndatas(RES_,dest,igr)+&
                  OP2P%ndim*OP2P%nobj_par(dest,igr)
          end if
       end do
       do igroup=1,OP2P%ngroupp
          igr=OP2P%group_id(igroup)
          source=OP2P%ranks(RECV_RES,igroup,OP2P%istep)
          if (source /= mpirank_null()) then
             OP2P%nres_comms=OP2P%nres_comms+1
             count=OP2P%ndim*OP2P%nobj_par(iproc,igr)
             if(OP2P%gpudirect/=1)then
               call mpirecv(OP2P%resw(igroup,OP2P%irecv_res)%ptr(1,1),count,&
                  source=source,tag=OP2P_tag(OP2P,source,back=.true.),&
                  comm=OP2P%mpi_comm,&
                  request=OP2P%requests_res(OP2P%nres_comms),simulate=OP2P%simulate,verbose=OP2P%verbose)
             else
               call mpirecv(OP2P%resw(igroup,OP2P%irecv_res)%ptr_gpu,count,&
                  source=source,tag=OP2P_tag(OP2P,source,back=.true.),&
                  comm=OP2P%mpi_comm,&
                  request=OP2P%requests_res(OP2P%nres_comms),simulate=OP2P%simulate,verbose=OP2P%verbose,&
                  type=MPI_DOUBLE_PRECISION)
             end if
             OP2P%ndatas(RES_,iproc,igr)=OP2P%ndatas(RES_,iproc,igr)-count
          end if
       end do

     end subroutine P2P_res

     subroutine prepare_calculation(iproc,OP2P,iter)
       use wrapper_MPI
       implicit none
       integer, intent(in) :: iproc!,norbp_max
       type(OP2P_data), intent(inout) :: OP2P
       type(OP2P_iterator), intent(inout) :: iter
       !local variables
       integer :: igr,source,isorb,jsorb

       igr=OP2P%group_id(OP2P%igroup)
       iter%igroup=igr
       iter%istep=OP2P%istep

       if (OP2P%istep == 0) then
          OP2P%do_calculation=.true.
          source=iproc
       else if (OP2P%ranks(RECV_DATA,OP2P%igroup,OP2P%istep-1) /= mpirank_null()) then
          OP2P%do_calculation=.true.
          !source=OP2P%ranks(RECV_DATA,OP2P%igroup,OP2P%istep-1)
          source=get_recvbuf_provenance(iproc,OP2P)
          if (iproc == OP2P%iproc_dump) then
             print '(5(1x,a,i8))','step',OP2P%istep,'group:',igr,&
                  ':processing',OP2P%ndim*OP2P%nobj_par(source,igr),&
                  'elements in',iproc,'from',source
          end if
       else
          OP2P%do_calculation=.false.
       end if
       if (.not. OP2P%do_calculation) return

       iter%remote_result=&
            OP2P%ranks(SEND_RES,OP2P%igroup,OP2P%istep) /= mpirank_null()
       OP2P%ndatac(OP2P%igroup)=OP2P%ndatac(OP2P%igroup)+&
            OP2P%ndim*OP2P%nobj_par(source,igr)
       !calculation of the partial densities and potentials
       !starting point of the loop
       !here there is the calculation routine
       !number of orbitals to be treated locally
       iter%nloc_i=OP2P%nobj_par(iproc,igr)
       iter%nloc_j=OP2P%nobj_par(source,igr)

       !calculating the starting orbitals locally
       iter%isloc_i=OP2P%objects_id(LOCAL_,iproc,igr)
       iter%isloc_j=OP2P%objects_id(LOCAL_,source,igr)

       !calculate the starting orbital globally
       isorb=OP2P%objects_id(GLOBAL_,iproc,igr)
       jsorb=OP2P%objects_id(GLOBAL_,source,igr)

       if (OP2P%istep/=0) then
          iter%phi_j=local_data_init(iter%nloc_j,OP2P%ndim)
          if (iter%remote_result) then
            if(OP2P%gpudirect/=1) then
             call set_local_data(iter%phi_j,jsorb,&
                  OP2P%dataw(OP2P%igroup,OP2P%isend_data)%ptr,OP2P%resw(OP2P%igroup,3)%ptr)
            else
             call set_local_data(iter%phi_j,jsorb,&
                  psir_gpu=OP2P%dataw(OP2P%igroup,OP2P%isend_data)%ptr_gpu,&
                  dpsir_gpu=OP2P%resw(OP2P%igroup,3)%ptr_gpu)
            end if
             !OP2P%dataw(1,1,OP2P%igroup,OP2P%isend_data),OP2P%resw(1,1,OP2P%igroup,3))
          else
            if(OP2P%gpudirect/=1) then
             call set_local_data(iter%phi_j,jsorb,&
                  OP2P%dataw(OP2P%igroup,OP2P%isend_data)%ptr)!OP2P%dataw(1,1,OP2P%igroup,OP2P%isend_data))
            else
             call set_local_data(iter%phi_j,jsorb,&
                  psir_gpu=OP2P%dataw(OP2P%igroup,OP2P%isend_data)%ptr_gpu)!OP2P%dataw(1,1,OP2P%igroup,OP2P%isend_data))
             end if
          end if
          !jorbs_tmp=1
          iter%isloc_j=1
       else
          iter%phi_j=iter%phi_i
          iter%isloc_j=iter%isloc_i
       end if
     end subroutine prepare_calculation


     !> Communication step using OP2P data + an iterator iter over OP2P.
     subroutine OP2P_communication_step(iproc,OP2P,iter)
       use wrapper_MPI
       use f_utils, only: f_zero
       implicit none
       integer, intent(in) :: iproc
       type(OP2P_data), intent(inout) :: OP2P
       type(OP2P_iterator), intent(inout) :: iter
       !local variables
       integer :: igroup,i_stat,norbp

       if (iter%event==OP2P_START) OP2P%istep=0 !to be moved at the initialization

       step_loop: do while (OP2P%istep <= OP2P%nstep)
          if (.not. OP2P%do_calculation) then
             OP2P%irecv_data=3-OP2P%isend_data
             OP2P%ndata_comms=0

             call P2P_data(iproc,OP2P,iter%phi_i)

             do igroup=1,OP2P%ngroupp
                if (OP2P%istep /= 0 .and. OP2P%ranks(SEND_RES,igroup,OP2P%istep) /= mpirank_null()) then
                   !put to zero the sending element
                   if(OP2P%gpudirect/=1)then
                     call f_zero(OP2P%resw(igroup,3)%ptr)
                   else
                     norbp=maxval(OP2P%nobj_par(:,OP2P%group_id(igroup)))
                     call cudamemset(OP2P%resw(igroup,3)%ptr_gpu, 0, OP2P%ndim*norbp,i_stat)
                   end if
                end if
             end do

             !calculation for orbitals to be performed
             OP2P%igroup=1
          end if
          group_loop: do while(OP2P%igroup <= OP2P%ngroupp)
             if (.not. OP2P%do_calculation) then
                call prepare_calculation(iproc,OP2P,iter)
             end if

             if (OP2P%do_calculation .and. iter%event==OP2P_START) then
                iter%event=OP2P_CALCULATE
                if (iter%istep == 0) then
                   iter%ncalls=iter%ncalls+(iter%nloc_i*(iter%nloc_j+1))/2
                else
                   iter%ncalls=iter%ncalls+iter%nloc_i*iter%nloc_j
                end if
                return !this is the point where the calculation starts in the outer loop
             end if
             iter%event=OP2P_START

             if (OP2P%do_calculation) then !this means that we have done the calculation before
                if (OP2P%istep/=0) call free_local_data(iter%phi_j)
             end if
             OP2P%igroup=OP2P%igroup+1
             OP2P%do_calculation=.false. !now the loop can cycle
             if (OP2P%igroup > OP2P%ngroupp) exit group_loop
          end do group_loop


          !verify that the messages have been passed
          call mpiwaitall(OP2P%ndata_comms,OP2P%requests_data,&
               simulate=OP2P%simulate)
          if(OP2P%gpudirect == 1) call synchronize()
          !if we come here this section can be done nonetheless
          call P2P_res(iproc,OP2P,iter%phi_i)!,OP2P%resw)

          if (OP2P%istep>1) OP2P%isend_res=3-OP2P%isend_res
          OP2P%isend_data=3-OP2P%isend_data
          OP2P%ndata_comms=0
          OP2P%istep=OP2P%istep+1
          if (OP2P%istep > OP2P%nstep) exit step_loop
       end do step_loop

       !retrieve result from GPU
       if(OP2P%gpudirect == 1) then
         call get_gpu_data(OP2P%ndim*sum(OP2P%nobj_par(iproc,:)),iter%phi_i%res,iter%phi_i%res_GPU)
         call synchronize()
         !call get_gpu_data(OP2P%ndim*sum(OP2P%nobj_par(iproc,:)),iter%phi_i%data,iter%phi_i%data_GPU)
         if(C_ASSOCIATED(iter%phi_i%data_GPU)) then
           call cudafree(iter%phi_i%data_GPU)
           iter%phi_i%data_GPU=C_NULL_PTR
         end if
         if(C_ASSOCIATED(iter%phi_i%res_GPU )) then
           call cudafree(iter%phi_i%res_GPU)
           iter%phi_i%res_GPU=C_NULL_PTR
         end if
       end if

       !release iterator
       call release_OP2P_iterator(iter)

     end subroutine OP2P_communication_step


     pure subroutine OP2P_info(iter,OP2P,percent,time_elapsed,time_remaining)
       use f_utils
       implicit none
       type(OP2P_data), intent(in) :: OP2P !<data structure
       type(OP2P_iterator), intent(in) :: iter !< present iterator
       integer, intent(out) :: percent !< percent of loop calculated
       real(f_double), intent(out) :: time_elapsed !< in seconds
       real(f_double), intent(out) :: time_remaining !< seconds, estimation
       time_elapsed=&
            (f_time()-iter%initialisation_time)*real(1.e-9,f_double)
       percent=nint(real(iter%ncalls,f_double)/real(OP2P%ncouples,f_double)*100.0_f_double)
       if (percent==0) then
          time_remaining=0.d0
       else
          time_remaining=time_elapsed*&
               (100.0_f_double/real(percent,f_double)-1.0_f_double)
       end if

     end subroutine OP2P_info


     !> Unitary test for the Overlap point-to-point.
     subroutine OP2P_unitary_test(mpi_comm,iproc,nproc,ngroup,ndim,nobj_par,symmetric,nearest_neighbor,assert)
       use yaml_output, only: yaml_map
       use yaml_strings
       use dictionaries, only: f_err_throw
       use f_utils
       implicit none
       !Arguments
       !>flag indicating the symmetricity of the operation. This reflects in the communication scheduling
       logical, intent(inout) :: symmetric
       integer, intent(in) :: mpi_comm,iproc,nproc,ngroup,ndim !< MPI data
       integer, dimension(0:nproc-1,ngroup), intent(in) :: nobj_par
       logical, intent(in), optional :: nearest_neighbor,assert
       !local variables
       logical :: asst
       real(wp) :: maxdiff
       type(OP2P_data) :: OP2P

       asst=.false.
       if (present(assert)) asst=assert
       !first initialize the OP2P data
       call initialize_OP2P_data(OP2P,mpi_comm,iproc,nproc,ngroup,ndim,nobj_par,0,symmetric,nearest_neighbor)

       if (.not. OP2P_test(iproc,nproc,OP2P,maxdiff,asst)) then
          if (iproc==0) call f_err_throw('OP2P Unitary test not passed, maxdiff='+maxdiff**'(1pe12.5)')
       end if
       if (asst) then
          call f_assert(maxdiff,id='OP2P unitary test',tol=1.e-10_wp)
       else if (iproc==0)  then
          call yaml_map('OP2P unitary test error',maxdiff)
       end if
       call free_OP2P_data(OP2P)
     end subroutine OP2P_unitary_test

     !> Test the coherence of the OP2P scheme within the chosen repartition.
     !! this subroutine might be useful to detect if some problem exists in a particular run.
     function OP2P_test(iproc,nproc,OP2P,maxdiff,quiet) result(passed)
       use yaml_output, only: yaml_comment
       use yaml_strings
       use wrapper_MPI
       use dynamic_memory
       use f_utils, only: f_assert
       implicit none
       !Arguments
       logical, intent(in) :: quiet
       integer, intent(in) :: iproc,nproc
       real(wp), intent(out) :: maxdiff
       type(OP2P_data), intent(inout) :: OP2P
       logical :: passed
       !local variables
       logical :: shared=.true.
       real(wp), parameter :: tol_maxdiff=1.e-10_wp
       integer :: norbp,prc
       real(wp) :: etot,tel,trm
       type(OP2P_iterator) :: iter
       !real(wp), dimension(:,:), allocatable :: data,res
       real(wp), dimension(:,:), pointer :: data,res !< these are declared as pointer to test the simgrid implementation

       passed=.false.
       norbp=sum(OP2P%nobj_par(iproc,:))

       data=f_malloc_ptr([OP2P%ndim,norbp],id='data')!,shared=shared)
       res=f_malloc0_ptr([OP2P%ndim,norbp],id='res')!,shared=shared)

       !To avoid too big numbers during the test.
       obj_delta = 1.d0/real(sum(OP2P%nobj_par),wp)
       group_delta = 1.d0/real(OP2P%ngroup*nproc,wp)

       call test_data(iproc,OP2P,norbp,data)

       call set_OP2P_iterator(iproc,OP2P,iter,norbp,data,res)

       etot=0.0_wp
        OP2P_loop: do
          call OP2P_communication_step(iproc,OP2P,iter)
          if (iter%event == OP2P_EXIT) exit
          !otherwise calculate
          call simulate_OP2P_calculation(iter%igroup,iter%istep,iter%remote_result,&
               iter%nloc_i,iter%nloc_j,iter%isloc_i,iter%isloc_j,&
               OP2P%ndim,iter%phi_i,iter%phi_j,etot)

          if (iproc==0 .and. .not. quiet) then
             call OP2P_info(iter,OP2P,prc,tel,trm)
             call yaml_comment('OP2P Simulation: '+prc**'(i3.3)'+'%; Time (s): Elapsed='+tel**'(1pg12.2)'&
                  +', Estimated Remaining='+trm**'(1pg12.2)')
          end if
       end do OP2P_loop

       !then check that the result coincide with the calculation
       call check_result(iproc,OP2P,norbp,res,maxdiff)

       if (nproc > 1) call mpiallred(maxdiff,1,op=MPI_MAX,comm=OP2P%mpi_comm)

!!$       passed=maxdiff < abs(data_val(1,1,1) - data_val(2,1,1)) + tol_maxdiff
       passed=maxdiff < tol_maxdiff

       call f_free_ptr(data)!,shared=shared)
       call f_free_ptr(res)!,shared=shared)

       call f_assert(.not. associated(data),id='Error, pointer "data" is still associated')
       call f_assert(.not. associated(res),id='Error, pointer "data" is still associated')

     end function OP2P_test

     subroutine test_data(iproc,OP2P,norbp,data)
       implicit none
       !Arguments
       integer, intent(in) :: norbp,iproc
       type(OP2P_data), intent(in) :: OP2P
       real(wp), dimension(OP2P%ndim,norbp), intent(out) :: data
       !local variables
       integer :: iobj,igroup,igr,iobj_loc,iobj_glob,i
       do igroup=1,OP2P%ngroupp
          igr=OP2P%group_id(igroup)
          do iobj=1,OP2P%nobj_par(iproc,igr)
             iobj_glob=OP2P%objects_id(GLOBAL_,iproc,igr)+iobj
             iobj_loc=OP2P%objects_id(LOCAL_,iproc,igr)-1+iobj
             do i=1,OP2P%ndim
                data(i,iobj_loc)=data_val(i,iobj_glob,igr)
             end do
          end do
       end do
     end subroutine test_data

     subroutine check_result(iproc,OP2P,norbp,res,maxdiff)
       use wrapper_MPI
       implicit none
       integer, intent(in) :: norbp,iproc
       type(OP2P_data), intent(in) :: OP2P
       real(wp), dimension(OP2P%ndim,norbp), intent(in) :: res
       real(wp), intent(out) :: maxdiff
       !local variables
       integer :: iobj,igroup,igr,iobj_loc,iobj_glob,i,nobj
       real(wp) :: ref

       maxdiff=0.0_wp
       do igroup=1,OP2P%ngroupp
          igr=OP2P%group_id(igroup)
          nobj=sum(OP2P%nobj_par(:,igr))
          do iobj=1,OP2P%nobj_par(iproc,igr)

             iobj_glob=OP2P%objects_id(GLOBAL_,iproc,igr)+iobj
             iobj_loc=OP2P%objects_id(LOCAL_,iproc,igr)-1+iobj

!!$             print *,'res',nobj,res(1,iobj_loc),res_val(1,iobj_glob,igr,OP2P%ndim,nobj),&
!!$                  (res(1,iobj_loc)-res_val(1,iobj_glob,igr,OP2P%ndim))/OP2P%ndim

             do i=1,OP2P%ndim
                ref=res_val(i,iobj_glob,igr,OP2P%ndim,mpisize(OP2P%mpi_comm),OP2P%ngroup,OP2P%nobj_par)
!!$                if (abs(res(i,iobj_loc)-ref) > 1.d-10) &
!!$                   & print *,iproc,i,iobj_loc,res(i,iobj_loc),ref,abs(res(i,iobj_loc)-ref)
!!$                   maxdiff=max(maxdiff,abs(res(i,iobj_loc)-ref))
                   maxdiff=max(maxdiff,abs(res(i,iobj_loc)/ref-1.0_wp))
             end do
          end do
       end do
     end subroutine check_result


     !> Define test value
     pure function data_val(i,iobj,igroup)
       implicit none
       integer, intent(in) :: i,iobj,igroup
       real(wp) :: data_val
       !1.0_wp
       data_val=(obj_delta*iobj)*(igroup)*group_delta!*i*elem_delta
     end function data_val


     !> Define the application of the operator to have a test result
     pure function op_val(ndim,iobj,jobj,igroup)
       implicit none
       !Arguments
       integer, intent(in) :: iobj,jobj,igroup,ndim
       real(wp) :: op_val
       !local variables
       real(wp) :: els

       els=real(ndim,wp)
       !els=(ndim*0.5_wp)*(ndim+1)*elem_delta**2!
       op_val=(els*obj_delta**2)*real(iobj,wp)*real(jobj,wp)*(group_delta*real(igroup,wp))**2

     end function op_val


     !> Define test result
     !!pure
     function res_val(i,iobj,igroup,ndim,nproc,ngroup,nobj_par)
       implicit none
       !Arguments
       integer, intent(in) :: i,iobj,igroup,ndim,nproc,ngroup
       integer, dimension(0:nproc-1,ngroup), intent(in) :: nobj_par
       real(wp) :: res_val
       !local variables
       integer :: jobj,jproc,kobj,jgroup

       res_val=0.0_wp
       kobj=0
       do jproc=0,nproc-1
          do jgroup=1,ngroup
             do jobj=1,nobj_par(jproc,jgroup)
                kobj=kobj+1
                if (jgroup==igroup) res_val=res_val+&
                     op_val(ndim,iobj,kobj,igroup)*data_val(i,kobj,igroup)
             end do
          end do
       end do

     end function res_val


   subroutine simulate_OP2P_calculation(igroup,istep,remote_result,&
        nloc_i,nloc_j,isloc_i,isloc_j,&
        ndim,phi_i,phi_j,rtot)
     use yaml_output, only: yaml_map
     use yaml_strings
     implicit none
     logical, intent(in) :: remote_result
     integer, intent(in) :: igroup
     integer, intent(in) :: istep !<step of the calculation
     integer, intent(in) :: nloc_i,nloc_j !<number of local elements to  be treated
     integer, intent(in) :: isloc_i !<starting point of the elements for phi_i
     integer, intent(in) :: isloc_j !<starting point of the elements for phi_j
     integer, intent(in) :: ndim
     type(local_data), intent(inout) :: phi_i,phi_j
     real(wp), intent(inout) :: rtot
     !local variables
     integer :: iorb,jorb,iorb_glb,jorb_glb,ishift,jshift,ishift_res,jshift_res,i
     real(wp) :: rint_ij
     !loop over all the orbitals
     !for the first step do only the upper triangular part
     do iorb=isloc_i,nloc_i+isloc_i-1
        do jorb=isloc_j,nloc_j+isloc_j-1
           !aliasing
           jorb_glb=phi_j%id_glb(jorb)
           iorb_glb=phi_i%id_glb(iorb)
           ishift=phi_i%displ(iorb)
           jshift=phi_j%displ(jorb)
           ishift_res=phi_i%displ_res(iorb)
           jshift_res=phi_j%displ_res(jorb)
           rint_ij=0.0_wp
           !do it only for upper triangular results
           if (istep /= 0 .or. jorb_glb >= iorb_glb) then
              do i=1,ndim
                 rint_ij=rint_ij+phi_i%data(i+ishift)*phi_j%data(i+jshift)
              end do
              if (abs(rint_ij-op_val(ndim,iorb_glb,jorb_glb,igroup)) > 0.1_wp*obj_delta**2) &
                   call yaml_map('Error for orbs '+yaml_toa([iorb_glb,jorb_glb]),&
                   [rint_ij,op_val(ndim,iorb_glb,jorb_glb,igroup)])
              !exact exchange energy
              if (iorb_glb == jorb_glb) then
                 rtot=rtot+rint_ij**2
              else
                 !if the result has to be sent away
                 if (remote_result .or. istep==0) then
                    rtot=rtot+2.0_wp*rint_ij**2
                 else !otherwise other processors are already calculating it
                    rtot=rtot+rint_ij**2
                 end if
              end if
              !accumulate the results for each of the wavefunctions concerned
              !$omp parallel do default(shared) private(i)
              do i=1,ndim
                 phi_i%res(i+ishift_res)=phi_i%res(i+ishift_res)+rint_ij*phi_j%data(i+jshift)
              end do
              !$omp end parallel do

              if ((iorb_glb /= jorb_glb .and. istep==0) .or. remote_result) then
                 !$omp parallel do default(shared) private(i)
                 do i=1,ndim
                    phi_j%res(i+jshift_res)=phi_j%res(i+jshift_res)+rint_ij*phi_i%data(i+ishift)
                 end do
                 !$omp end parallel do
              end if
           end if
        end do
     end do

   end subroutine simulate_OP2P_calculation


!!$   !> Initialise the data needed to manage communication operations
!!$   !objects_attributes(:,1) <= group to which the object belongs
!!$   !objects_attributes(:,2) <= size in number of elements of the object
!!$   !objects_attributes(:,3) <= size in number of elements of the results of the operations associated to the object
!!$   !objects_repartition(:) <= distribution of the objects among processors
!!$   subroutine initialize_OP2P_descriptors(symop,iproc,nproc,nobjects,objects_attributes,objects_repartition,OP2P)
!!$     use dynamic_memory
!!$     use module_defs
!!$      implicit none
!!$      logical, intent(in) :: symop !< defines whether the operator will be symmetric
!!$      integer, intent(in) :: iproc,nproc,nobjects
!!$      integer, dimension(0:nproc-1), intent(in) :: objects_repartition !< the sum is the number of objects
!!$      integer, dimension(nobjects,3), intent(in) :: objects_attributes
!!$      type(OP2P_descriptors), intent(out) :: OP2P
!!$      !local variables
!!$      character(len=*), parameter :: subname='initialize_OP2P_communications'
!!$      !integer :: ndebug=0  !< to be removed whenever with module_base
!!$      integer :: igroup,iobject,jproc,ioffset_local,ioffset_global,iobj,nsize,igroup_previous
!!$      integer :: nprocgr_max,iprocgrs,iprocgrr,icount,istep,kproc,nstepsm1
!!$      integer :: iaddress_local,iaddress_results_local,nsize_results
!!$
!!$      OP2P%forsymop=symop !< Assign the symmetry constraint to the structure
!!$
!!$      !calculate total number of groups
!!$      OP2P%ngroup=0
!!$      do iobject=1,nobjects
!!$         OP2P%ngroup=max(OP2P%ngroup,objects_attributes(iobject,1))
!!$      end do
!!$      !verify that all the groups exists
!!$      parse_groups: do igroup=1,OP2P%ngroup
!!$         do iobject=1,nobjects
!!$            if (objects_attributes(iobject,1)==igroup) cycle parse_groups
!!$         end do
!!$         write(*,*)'ERROR: group id',igroup,' not found in the attributes'
!!$         stop
!!$      end do parse_groups
!!$
!!$      !allocate arrays which depends of the number of groups
!!$      OP2P%nvctr_par = f_malloc_ptr((/ 0.to.nproc-1, 1.to.OP2P%ngroup, 1.to.2 /),id='OP2P%nvctr_par')
!!$      OP2P%ioffp_group = f_malloc_ptr((/ 1.to.5, 0.to.nproc-1, 1.to.OP2P%ngroup /),id='OP2P%ioffp_group')
!!$
!!$      !fill these arrays
!!$      !initialise the arrays
!!$      do igroup=1,OP2P%ngroup
!!$         do jproc=0,nproc-1
!!$            OP2P%nvctr_par(jproc,igroup,1)=0 !<number of elements for the objects
!!$            OP2P%nvctr_par(jproc,igroup,2)=0 !<number of elements for the results
!!$            OP2P%ioffp_group(1,jproc,igroup)=UNINITIALIZED(1) !< global object offset !fake value for cross-check initialisation
!!$            OP2P%ioffp_group(2,jproc,igroup)=UNINITIALIZED(1) !< local object offset fake value for cross-check initialisation
!!$            OP2P%ioffp_group(3,jproc,igroup)=1  !< local address position
!!$            OP2P%ioffp_group(4,jproc,igroup)=0  !< local number of objects starting from local object
!!$            OP2P%ioffp_group(5,jproc,igroup)=1  !< local address position of the result
!!$         end do
!!$      end do
!!$
!!$      iobject=0
!!$      ioffset_global=0 !< object to which a given couple group-processor is associated
!!$      do jproc=0,nproc-1
!!$         igroup_previous=UNINITIALIZED(1)
!!$         ioffset_local=0
!!$         iaddress_local=1
!!$         iaddress_results_local=1
!!$         do iobj=1,objects_repartition(jproc)
!!$            iobject=iobject+1
!!$
!!$            igroup=objects_attributes(iobject,1)
!!$            nsize=objects_attributes(iobject,2)
!!$            nsize_results=objects_attributes(iobject,3)
!!$            !count the number of elements for each group and processor
!!$            OP2P%nvctr_par(jproc,igroup,1)=OP2P%nvctr_par(jproc,igroup,1)+nsize
!!$            OP2P%nvctr_par(jproc,igroup,2)=OP2P%nvctr_par(jproc,igroup,2)+nsize_results
!!$            !any time that the group considered changes update the array of the offsets
!!$            if (igroup_previous /= igroup) then
!!$               !the array ioffp_group can be filled only once.
!!$               !if it is not the case this means that the same group is
!!$               !not contiguous in a given processor. This is forbidden by the parallelisation scheme
!!$               if (OP2P%ioffp_group(1,jproc,igroup) /= UNINITIALIZED(1)) then
!!$                  write(*,*)'ERROR (global): the group',igroup,' is non contiguously distributed in processor ',jproc
!!$                  stop
!!$               else
!!$                  OP2P%ioffp_group(1,jproc,igroup)=ioffset_global
!!$               end if
!!$               if (OP2P%ioffp_group(2,jproc,igroup) /= UNINITIALIZED(1)) then
!!$                  write(*,*)'ERROR (local): the group',igroup,' is non contiguously distributed in processor ',jproc
!!$                  stop
!!$               else
!!$                  OP2P%ioffp_group(2,jproc,igroup)=ioffset_local
!!$               end if
!!$               OP2P%ioffp_group(3,jproc,igroup)=iaddress_local
!!$               OP2P%ioffp_group(4,jproc,igroup)=1
!!$               OP2P%ioffp_group(5,jproc,igroup)=iaddress_results_local
!!$               igroup_previous=igroup
!!$            else
!!$               OP2P%ioffp_group(4,jproc,igroup)=OP2P%ioffp_group(4,jproc,igroup)+1
!!$            end if
!!$            !the offset is expressed in number of objects
!!$            ioffset_global=ioffset_global+1
!!$            ioffset_local=ioffset_local+1
!!$            iaddress_local=iaddress_local+nsize
!!$            iaddress_results_local=iaddress_results_local+nsize_results
!!$         end do
!!$      end do
!!$      !check
!!$      if (iobject /= nobjects) stop 'ERROR, objects_repartition'
!!$
!!$      !clean the information for the offset, for the first part of the array
!!$      do igroup=1,OP2P%ngroup
!!$         do jproc=0,nproc-1
!!$            if (OP2P%ioffp_group(1,jproc,igroup)==UNINITIALIZED(1)) OP2P%ioffp_group(1,jproc,igroup)=0
!!$            if (OP2P%ioffp_group(2,jproc,igroup)==UNINITIALIZED(1)) OP2P%ioffp_group(2,jproc,igroup)=0
!!$         end do
!!$      end do
!!$
!!$      OP2P%ngroupp = f_malloc_ptr(0.to.nproc-1,id='OP2P%ngroupp')
!!$
!!$      !calculate the number of groups which belong to each processor
!!$      !here we can allocate the working arrays giving the maximum
!!$      !between the components for each group
!!$      OP2P%ngroupp_max=0
!!$      OP2P%ncomponents_max=0
!!$      OP2P%ncomponents_results_max=0
!!$      OP2P%iprocref=0 !processor which has the maximum number of groups
!!$      do jproc=0,nproc-1
!!$         OP2P%ngroupp(jproc)=0
!!$         do igroup=1,OP2P%ngroup
!!$            OP2P%ncomponents_max=max(OP2P%ncomponents_max,OP2P%nvctr_par(jproc,igroup,1))
!!$            OP2P%ncomponents_results_max=max(OP2P%ncomponents_results_max,OP2P%nvctr_par(jproc,igroup,2))
!!$            if (OP2P%nvctr_par(jproc,igroup,1) > 0) then !should be identical by considering objects or results
!!$               OP2P%ngroupp(jproc)=OP2P%ngroupp(jproc)+1
!!$            end if
!!$         end do
!!$         if (OP2P%ngroupp_max < OP2P%ngroupp(jproc)) OP2P%iprocref=jproc
!!$         OP2P%ngroupp_max=max(OP2P%ngroupp_max,OP2P%ngroupp(jproc))
!!$      end do
!!$
!!$
!!$      OP2P%nprocgr = f_malloc_ptr(OP2P%ngroup,id='OP2P%nprocgr')
!!$
!!$      !calculate the number of processors which belong to each group
!!$      !here we can allocate the working arrays giving the maximum
!!$      !between the components for each group, both for objects and results
!!$      nprocgr_max=0
!!$      do igroup=1,OP2P%ngroup
!!$         OP2P%nprocgr(igroup)=0
!!$         do jproc=0,nproc-1
!!$            if (OP2P%nvctr_par(jproc,igroup,1) > 0) then !should be identical by considering objects or results
!!$               OP2P%nprocgr(igroup)=OP2P%nprocgr(igroup)+1
!!$            end if
!!$         end do
!!$         nprocgr_max=max(nprocgr_max,OP2P%nprocgr(igroup))
!!$      end do
!!$      if (OP2P%forsymop) then
!!$         OP2P%nsteps_max=(nprocgr_max-1)/2+1 !here the number of steps should be changed for non-symmetric operation
!!$      else
!!$         OP2P%nsteps_max=(nprocgr_max-1)
!!$      end if
!!$      !print *,'nsteps',OP2P%nsteps_max
!!$      !determine the array of the groups which are of interest for this processor
!!$      OP2P%igrpr = f_malloc_ptr((/ 1.to.OP2P%ngroupp_max, 0.to.nproc-1 /),id='OP2P%igrpr')
!!$      !processors lying above and below iproc in the list of communicating process
!!$      OP2P%iprocpm1 = f_malloc_ptr((/ 1.to.2, 0.to.nprocgr_max, 1.to.OP2P%ngroupp_max, 0.to.nproc-1 /),id='OP2P%iprocpm1')
!!$
!!$      !determine for each processor the groups which has to be used
!!$      OP2P%iprocpm1(:,:,:,:)=UNINITIALIZED(1)
!!$      do jproc=0,nproc-1
!!$         !groups which are associated to a given processor
!!$         icount=0
!!$         do igroup=1,OP2P%ngroup
!!$            if (OP2P%nvctr_par(jproc,igroup,1) > 0) then
!!$               icount=icount+1
!!$               OP2P%igrpr(icount,jproc)=igroup
!!$            end if
!!$         end do
!!$
!!$         !calculate the processor which lies after and before the present in the list
!!$         do igroup=1,OP2P%ngroupp(jproc)
!!$            iprocgrs=-1 !<= distance from the processor for ascending order
!!$            iprocgrr=-1 !<= distance from the processor for descending order
!!$            !define the number of data to calculate in total
!!$            do kproc=0,nproc-1
!!$               if (OP2P%nvctr_par(modulo(jproc+kproc,nproc),OP2P%igrpr(igroup,jproc),1) > 0) then
!!$                  iprocgrs=iprocgrs+1
!!$                  OP2P%iprocpm1(1,iprocgrs,igroup,jproc)=modulo(jproc+kproc,nproc)
!!$               end if
!!$               if (OP2P%nvctr_par(modulo(jproc-kproc,nproc),OP2P%igrpr(igroup,jproc),1) > 0) then
!!$                  iprocgrr=iprocgrr+1
!!$                  OP2P%iprocpm1(2,iprocgrr,igroup,jproc)=modulo(jproc-kproc,nproc)
!!$               end if
!!$            end do
!!$         end do
!!$      end do
!!$
!!$      !print *,'a',igrpr(:,:),iprocpm1,nvctr_par
!!$      !stop
!!$
!!$      !calculate the list of send-receive operations which have to be performed per group
!!$      !allocate it at the maximum size needed (to be changed if symmetric
!!$      OP2P%communication_schedule = f_malloc_ptr((/ 1.to.4, 0.to.OP2P%nsteps_max, 1.to.OP2P%ngroupp_max, 0.to.nproc-1 /),&
!!$          id='OP2P%communication_schedule')
!!$
!!$      !un-initalize array, no communication in any step
!!$      OP2P%communication_schedule(:,:,:,:)=UNINITIALIZED(1)
!!$
!!$      do jproc=0,nproc-1
!!$         do igroup=1,OP2P%ngroupp(jproc)
!!$            if (OP2P%forsymop) then
!!$               !here the number of steps should be changed for non-symmetric operation
!!$               nstepsm1=(OP2P%nprocgr(OP2P%igrpr(igroup,jproc))-1)/2-1
!!$            else
!!$               nstepsm1=(OP2P%nprocgr(OP2P%igrpr(igroup,jproc))-1)
!!$            end if
!!$            !do not send anything if there is only one member in the group
!!$            if (OP2P%nprocgr(OP2P%igrpr(igroup,jproc)) > 1) then
!!$               do istep=0,nstepsm1
!!$                  !define the arrays for send-receive of data
!!$                  OP2P%communication_schedule(1,istep,igroup,jproc)=&
!!$                       OP2P%iprocpm1(2,istep,igroup,jproc)
!!$                  OP2P%communication_schedule(2,istep,igroup,jproc)=&
!!$                       OP2P%iprocpm1(2,istep+1,igroup,jproc)
!!$                  if (istep > 0) then
!!$                     OP2P%communication_schedule(3,istep,igroup,jproc)=&
!!$                          OP2P%iprocpm1(2,istep,igroup,jproc)
!!$                     OP2P%communication_schedule(4,istep,igroup,jproc)=&
!!$                          OP2P%iprocpm1(1,istep,igroup,jproc)
!!$                  end if
!!$               end do
!!$               if (OP2P%forsymop) then
!!$                  istep=nstepsm1+1
!!$                  !the last step behaves differently if the group number is odd or even
!!$                  if (modulo(OP2P%nprocgr(OP2P%igrpr(igroup,jproc)),2) == 0) then
!!$                     OP2P%communication_schedule(1,istep,igroup,jproc)=&
!!$                          OP2P%iprocpm1(2,istep,igroup,jproc)
!!$                     OP2P%communication_schedule(2,istep,igroup,jproc)=&
!!$                          OP2P%iprocpm1(2,istep+1,igroup,jproc)
!!$                     if (istep > 0) then
!!$                        OP2P%communication_schedule(3,istep,igroup,jproc)=&
!!$                             OP2P%iprocpm1(2,istep,igroup,jproc)
!!$                        OP2P%communication_schedule(4,istep,igroup,jproc)=&
!!$                             OP2P%iprocpm1(1,istep,igroup,jproc)
!!$                     end if
!!$                  else
!!$                     OP2P%communication_schedule(3,istep,igroup,jproc)=&
!!$                          OP2P%iprocpm1(2,istep,igroup,jproc)
!!$                     OP2P%communication_schedule(4,istep,igroup,jproc)=&
!!$                          OP2P%iprocpm1(1,istep,igroup,jproc)
!!$                  end if
!!$               end if
!!$            end if
!!$         end do
!!$         !if (iproc==0 .and. jproc==1) print *,'iproc',jproc,OP2P%communication_schedule(3:4,0:1,:,jproc)
!!$      end do
!!$
!!$      !after initialisation, the results of the groups can be printed
!!$      if (iproc ==0) call print_group_schemes(6,nproc,OP2P)
!!$
!!$   END SUBROUTINE initialize_OP2P_descriptors
!!$
!!$
!!$   subroutine print_group_schemes(unit,nproc,OP2P)
!!$     use module_defs
!!$      implicit none
!!$      !Arguments
!!$      integer, intent(in) :: nproc,unit
!!$      type(OP2P_descriptors), intent(in) :: OP2P
!!$      !local variables
!!$      integer :: jproc,nvctrp,igroup,nsteps,i,istep
!!$
!!$      write(unit,'(1x,a,a)')repeat('-',45),'Overlap point-to-point data repartition'
!!$      write(unit,'(1x,8(a))')'| proc |',' No. Groups  |  Grp | #Obj- #Res ',&
!!$         &   '|| N. Components | Steps|    Components   |'
!!$      do jproc=0,nproc-1
!!$         nvctrp=0
!!$         do igroup=1,OP2P%ngroupp(jproc)
!!$            nvctrp=nvctrp+&
!!$               &   OP2P%nvctr_par(jproc,OP2P%igrpr(igroup,jproc),1)
!!$         end do
!!$         !print total number of orbitals and components
!!$         write(unit,'(1x,a,i4,a,i8,a,i13,a)')'| ',jproc,' |',OP2P%ngroupp(jproc),&
!!$            &   repeat(' ',5)//'|'//repeat('-',6)//'|'//repeat('-',12)//'||',&
!!$            &   nvctrp,&
!!$            &   repeat(' ',2)//'|'//repeat('-',6)//'|'//repeat('-',17)//'|'
!!$         !change the values to zero if there is no orbital
!!$
!!$         do igroup=1,OP2P%ngroupp(jproc)
!!$            nsteps=0
!!$            do istep=0,OP2P%nsteps_max
!!$               do i=1,4
!!$                  if (OP2P%communication_schedule(i,istep,igroup,jproc) /= UNINITIALIZED(1)) then
!!$                     nsteps=nsteps+1
!!$                     exit
!!$                  end if
!!$               end do
!!$            end do
!!$            write(unit,'(a,i4,a,i5,a,i5,a,i4,a,i8,a,i8,a)')&
!!$               &   ' |'//repeat(' ',6)//'|'//repeat(' ',13)//'|',&
!!$               &   OP2P%igrpr(igroup,jproc),'  |',OP2P%nvctr_par(jproc,OP2P%igrpr(igroup,jproc),1),&
!!$               &   '-',OP2P%nvctr_par(jproc,OP2P%igrpr(igroup,jproc),2),&
!!$               &   ' ||'//repeat(' ',15)//'|',&
!!$               &   nsteps,'  |',1,'-',1,'|'
!!$         end do
!!$      end do
!!$      write(unit,'(1x,a,a)')repeat('-',84)
!!$
!!$   END SUBROUTINE print_group_schemes
!!$
!!$
!!$   subroutine OP2P_communication(iproc,nproc,OP2P,objects_data,results_data,apply_symmetric_operator,&
!!$        &   send_op,receive_op,wait_op)
!!$     use module_base
!!$      implicit none
!!$      interface
!!$         subroutine send_op(istep,isendproc,irecvproc,ncount,itag,irequest,sendbuf)
!!$            integer, intent(in) :: istep,isendproc,irecvproc,ncount,itag,irequest
!!$            real(kind=8), intent(in) :: sendbuf
!!$         END SUBROUTINE send_op
!!$
!!$         subroutine receive_op(istep,isendproc,irecvproc,ncount,itag,irequest,recvbuf)
!!$            integer, intent(in) :: istep,isendproc,irecvproc,ncount,itag,irequest
!!$            real(kind=8), intent(in) :: recvbuf
!!$         END SUBROUTINE receive_op
!!$
!!$         subroutine wait_op(iproc,istep,nreq,requests)
!!$            implicit none
!!$            integer, intent(in) :: iproc,istep,nreq
!!$            integer, dimension(nreq), intent(in) :: requests
!!$         END SUBROUTINE wait_op
!!$
!!$         !here a procedure can be added if the objects to be sent are not of double precision
!!$         subroutine apply_symmetric_operator(istep,iproc,igroup,remote_result,idata_glob,jdata_glob,&
!!$               &   idata_loc,jdata_loc,ndatai,ndataj,nvctri,nvctrj,nvctri_results,nvctrj_results,&
!!$               &   objects_data_i,objects_data_j,&
!!$               &   results_data_i,results_data_j)
!!$            implicit none
!!$            logical, intent(in) :: remote_result
!!$            integer, intent(in) :: istep,iproc,igroup,idata_glob,jdata_glob,idata_loc,jdata_loc,ndatai,ndataj
!!$            integer, intent(in) :: nvctri,nvctrj,nvctri_results,nvctrj_results
!!$            real(kind=8), dimension(nvctri), intent(in) :: objects_data_i
!!$            real(kind=8), dimension(nvctrj), intent(in) :: objects_data_j
!!$            real(kind=8), dimension(nvctri_results), intent(inout) :: results_data_i
!!$            real(kind=8), dimension(nvctrj_results), intent(inout) :: results_data_j
!!$         END SUBROUTINE apply_symmetric_operator
!!$
!!$      end interface
!!$
!!$      integer, intent(in) :: iproc,nproc
!!$      type(OP2P_descriptors), intent(in) :: OP2P
!!$      real(kind=8), dimension(*), intent(in) :: objects_data !< the dimension of the initial objects is not specified
!!$      real(kind=8), dimension(*), intent(out) :: results_data
!!$      optional :: send_op,receive_op,wait_op
!!$
!!$      !local variables
!!$      character(len=*), parameter :: subname='op2p_communication'
!!$      logical :: doit,remote_result
!!$      integer :: isnow,ncommsstep,irnow,igroup,istep,isnow_results,irnow_results,ncommsstep_results,iaddress_local
!!$      integer :: istart_results,nvctri,nvctrj,nvctri_results,nvctrj_results
!!$      integer :: isorb,jsorb,iorbs,jorbs,norbi,norbj,jproc,istart,jproc_to_send,jproc_to_recv,nelems_to_send,nelems_to_recv
!!$      integer, dimension(:,:), allocatable :: mpireq
!!$      real(kind=8), dimension(:,:,:), allocatable :: sendreceive_buffer,restemp_buffer
!!$
!!$      !print *,'entering',iproc,OP2P%ngroupp(iproc)
!!$
!!$      !quick return if the number of groups is zero here
!!$      if (OP2P%ngroupp(iproc) == 0) return
!!$
!!$      !allocate the array of sendreceive buffers
!!$      sendreceive_buffer = f_malloc((/ OP2P%ncomponents_max, 2, OP2P%ngroupp(iproc) /),id='sendreceive_buffer')
!!$      !allocate the results buffer only in the case of symmetric OP2P communication
!!$      !if (OP2P%forsym) then
!!$      restemp_buffer = f_malloc((/ OP2P%ncomponents_results_max, 3, OP2P%ngroupp(iproc) /),id='restemp_buffer')
!!$      !end if
!!$      mpireq = f_malloc((/ 2*OP2P%ngroupp_max, 2 /),id='mpireq')
!!$      !ncalls=0
!!$      !real communication
!!$      isnow=1
!!$      isnow_results=1
!!$      irnow_results=1
!!$      ncommsstep_results=0
!!$      do istep=0,OP2P%nsteps_max
!!$         !print *,'istep,iproc',istep,iproc,OP2P%nsteps_max
!!$         irnow=3-isnow
!!$         ncommsstep=0
!!$         !sending receiving data
!!$         do igroup=1,OP2P%ngroupp(iproc)
!!$            if (OP2P%communication_schedule(1,istep,igroup,iproc) /= UNINITIALIZED(1)) then
!!$               ncommsstep=ncommsstep+1 !just check the receives
!!$               jproc_to_send=OP2P%iprocpm1(1,1,igroup,iproc)
!!$               if (OP2P%ngroupp(jproc_to_send) == 0 ) then
!!$                  print *,'ERROR,iproc',iproc
!!$                  stop
!!$               end if
!!$               nelems_to_send=OP2P%nvctr_par(OP2P%communication_schedule(1,istep,igroup,iproc),OP2P%igrpr(igroup,iproc),1) !objects
!!$               iaddress_local=OP2P%ioffp_group(3,iproc,OP2P%igrpr(igroup,iproc))
!!$               if (istep == 0) then
!!$                  if (present(send_op)) then
!!$                     call send_op(istep,iproc,jproc_to_send,nelems_to_send,&
!!$                        &   iproc+2*nproc*istep,mpireq(ncommsstep,1),objects_data(iaddress_local))
!!$                  else
!!$                     call send_mpi(istep,jproc_to_send,nelems_to_send,&
!!$                        &   iproc+2*nproc*istep,mpireq(ncommsstep,1),objects_data(iaddress_local))
!!$                  end if
!!$               else
!!$                  !multiply by two the sending objects for the accumulation array
!!$                  if (present(send_op)) then
!!$                     call send_op(istep,iproc,jproc_to_send,nelems_to_send,&
!!$                        &   iproc+2*nproc*istep,mpireq(ncommsstep,1),sendreceive_buffer(1,isnow,igroup))
!!$                  else
!!$                     call send_mpi(istep,jproc_to_send,nelems_to_send,&
!!$                        &   iproc+2*nproc*istep,mpireq(ncommsstep,1),sendreceive_buffer(1,isnow,igroup))
!!$                  end if
!!$               end if
!!$            end if
!!$            if (OP2P%communication_schedule(2,istep,igroup,iproc) /= UNINITIALIZED(1)) then
!!$               ncommsstep=ncommsstep+1
!!$               jproc_to_recv=OP2P%iprocpm1(2,1,igroup,iproc)
!!$               if (OP2P%ngroupp(jproc_to_recv) == 0 ) then
!!$                  print *,'ERROR(recv),iproc',iproc
!!$                  stop
!!$               end if
!!$               nelems_to_recv=OP2P%nvctr_par(OP2P%communication_schedule(2,istep,igroup,iproc),OP2P%igrpr(igroup,iproc),1) !objects
!!$               iaddress_local=OP2P%ioffp_group(3,iproc,OP2P%igrpr(igroup,iproc))
!!$               if (present(receive_op)) then
!!$                  call receive_op(istep,jproc_to_recv,iproc,nelems_to_recv,&
!!$                     &   jproc_to_recv+2*nproc*istep,mpireq(ncommsstep,1),sendreceive_buffer(1,irnow,igroup))
!!$               else
!!$                  call receive_mpi(istep,jproc_to_recv,iproc,nelems_to_recv,&
!!$                     &   jproc_to_recv+2*nproc*istep,mpireq(ncommsstep,1),sendreceive_buffer(1,irnow,igroup))
!!$               end if
!!$            end if
!!$         end do
!!$         !print *,'starting',iproc,istep,ncommsstep,OP2P%nsteps_max
!!$         !at this point the first pool of data should have been sent
!!$         !the operation can be performed
!!$         do igroup=1,OP2P%ngroupp(iproc)
!!$            !decide if the operation has to be performed (if something has been received)
!!$            doit = (istep == 0)
!!$            !to avoid boundary problems in the previous if statement
!!$            if (.not. doit) doit = OP2P%communication_schedule(2,istep-1,igroup,iproc) /=UNINITIALIZED(1)
!!$            if (doit) then
!!$               !starting object (global)
!!$               isorb=OP2P%ioffp_group(1,iproc,OP2P%igrpr(igroup,iproc))
!!$               !starting object (local)
!!$               iorbs=OP2P%ioffp_group(2,iproc,OP2P%igrpr(igroup,iproc))
!!$               !number of objects to be treated locally for iproc
!!$               norbi=OP2P%ioffp_group(4,iproc,OP2P%igrpr(igroup,iproc))
!!$               !number of components associated to the object array
!!$               nvctri=OP2P%nvctr_par(iproc,OP2P%igrpr(igroup,iproc),1)
!!$
!!$               if (istep == 0) then
!!$                  jproc=iproc
!!$               else
!!$                  jproc=OP2P%communication_schedule(2,istep-1,igroup,iproc)
!!$               end if
!!$               !starting address on the local array
!!$               istart=OP2P%ioffp_group(3,iproc,OP2P%igrpr(igroup,iproc))
!!$
!!$               !starting object (global)
!!$               jsorb=OP2P%ioffp_group(1,jproc,OP2P%igrpr(igroup,iproc))
!!$               !starting object (local)
!!$               jorbs=OP2P%ioffp_group(2,jproc,OP2P%igrpr(igroup,iproc))
!!$               !number of objects to be treated locally for iproc
!!$               norbj=OP2P%ioffp_group(4,jproc,OP2P%igrpr(igroup,iproc))
!!$               !number of components associated to the object array
!!$               nvctrj=OP2P%nvctr_par(jproc,OP2P%igrpr(igroup,iproc),1)
!!$
!!$               !starting address on the results_array
!!$               istart_results=OP2P%ioffp_group(5,iproc,OP2P%igrpr(igroup,iproc))
!!$               !number of components associated to the results array
!!$               nvctri_results=OP2P%nvctr_par(iproc,OP2P%igrpr(igroup,iproc),2)
!!$               !number of components associated to the results array
!!$               nvctrj_results=OP2P%nvctr_par(jproc,OP2P%igrpr(igroup,iproc),2)
!!$
!!$
!!$               !print *,'istep,iproc,istart_results',istep,iproc,istart_results
!!$               !do remote operation for symmetric cases
!!$               remote_result=OP2P%forsymop .and. &
!!$                  &   (istep /=0 .and. OP2P%communication_schedule(3,istep,igroup,iproc) /= UNINITIALIZED(1))
!!$               if (istep > 0) then
!!$                  call apply_symmetric_operator(istep,iproc,OP2P%igrpr(igroup,iproc),remote_result,&
!!$                     &   isorb,jsorb,iorbs,jorbs,norbi,norbj,nvctri,nvctrj,nvctri_results,nvctrj_results,&
!!$                     &   objects_data(istart),sendreceive_buffer(1,isnow,igroup),&
!!$                     &   results_data(istart_results),& !the result may have a different size than the wavefunction
!!$                  restemp_buffer(1,3,igroup))
!!$               else
!!$                  call apply_symmetric_operator(istep,iproc,OP2P%igrpr(igroup,iproc),remote_result,&
!!$                     &   isorb,jsorb,iorbs,jorbs,norbi,norbj,nvctri,nvctrj,nvctri_results,nvctrj_results,&
!!$                     &   objects_data(istart),objects_data(istart),&
!!$                  results_data(istart_results),& !the result may have a different size than the wavefunction
!!$                  restemp_buffer(1,3,igroup))
!!$               end if
!!$            end if
!!$         end do
!!$         !print *,'ending',iproc,istep
!!$
!!$         !check the sending of the results array (this operation can also be performed at the end of the cycle
!!$         if (ncommsstep_results > 0) then
!!$            if (present(wait_op)) then
!!$               call wait_op(iproc,istep,ncommsstep_results,mpireq(1,2))
!!$            else
!!$               call wait_mpi(iproc,istep,ncommsstep_results,mpireq(1,2))
!!$            end if
!!$            !copy the results which have been received (the messages sending are after)
!!$            !to be modified via the creation of an array which follows psi
!!$            do igroup=1,OP2P%ngroupp(iproc)
!!$               !starting address on the local array (supposing that the array and the results have the same size)
!!$               istart_results=OP2P%ioffp_group(5,iproc,OP2P%igrpr(igroup,iproc))
!!$               if (OP2P%communication_schedule(4,istep-1,igroup,iproc) /= UNINITIALIZED(1)) then
!!$                  !reduce temporary result
!!$                  !this routine has to be defined outside from the module
!!$                  call daxpy(OP2P%nvctr_par(iproc,OP2P%igrpr(igroup,iproc),2),1.0d0,restemp_buffer(1,irnow_results,igroup),1,&
!!$                     &   results_data(istart_results),1)
!!$                  !print *,'iproc,reduce',iproc,istep,results_data(istart_results),restemp_buffer(1,irnow_results,igroup)
!!$               end if
!!$            end do
!!$         end if
!!$
!!$         ncommsstep_results=0
!!$         !meanwhile, we can receive the result from the processor which has the psi
!!$         irnow_results=3-isnow_results
!!$         do igroup=1,OP2P%ngroupp(iproc)
!!$            if (OP2P%communication_schedule(3,istep,igroup,iproc) /= UNINITIALIZED(1)) then
!!$               ncommsstep_results=ncommsstep_results+1 !only receive is taken into account
!!$               jproc_to_send=OP2P%communication_schedule(3,istep,igroup,iproc)
!!$               nelems_to_send=OP2P%nvctr_par(OP2P%communication_schedule(3,istep,igroup,iproc),OP2P%igrpr(igroup,iproc),2) !results
!!$
!!$               !copy data before sending (to be performed in case the previous send has not finished)
!!$               call vcopy(nelems_to_send,restemp_buffer(1,3,igroup),1,&
!!$                  &   restemp_buffer(1,isnow_results,igroup),1) !is this copy unavoidable? unfortunately yes...
!!$
!!$               if (present(send_op)) then
!!$                  call send_op(istep,iproc,jproc_to_send,nelems_to_send,&
!!$                     &   iproc+nproc+2*nproc*istep,mpireq(ncommsstep_results,2),restemp_buffer(1,isnow_results,igroup))
!!$               else
!!$                  call send_mpi(istep,jproc_to_send,nelems_to_send,&
!!$                     &   iproc+nproc+2*nproc*istep,mpireq(ncommsstep_results,2),restemp_buffer(1,isnow_results,igroup))
!!$               end if
!!$            end if
!!$            if (OP2P%communication_schedule(4,istep,igroup,iproc) /= UNINITIALIZED(1)) then
!!$               ncommsstep_results=ncommsstep_results+1
!!$               jproc_to_recv=OP2P%communication_schedule(4,istep,igroup,iproc)
!!$               nelems_to_recv=OP2P%nvctr_par(iproc,OP2P%igrpr(igroup,iproc),2) !results
!!$               if (present(receive_op)) then
!!$                  call receive_op(istep,jproc_to_recv,iproc,nelems_to_recv,&
!!$                     &   jproc_to_recv+nproc+2*nproc*istep,mpireq(ncommsstep_results,2),&
!!$                     &   restemp_buffer(1,irnow_results,igroup))
!!$               else
!!$                  call receive_mpi(istep,jproc_to_recv,iproc,nelems_to_recv,&
!!$                     &   jproc_to_recv+nproc+2*nproc*istep,mpireq(ncommsstep_results,2),&
!!$                     &   restemp_buffer(1,irnow_results,igroup))
!!$               end if
!!$            end if
!!$         end do
!!$         if (istep>1) isnow_results=3-isnow_results
!!$
!!$         if (ncommsstep /=0) then
!!$            if (present(wait_op)) then
!!$               call wait_op(iproc,istep,ncommsstep,mpireq(1,1))
!!$            else
!!$               call wait_mpi(iproc,istep,ncommsstep,mpireq(1,1))
!!$            end if
!!$         end if
!!$         isnow=3-isnow
!!$         ncommsstep=0
!!$         !print *,'iproc,istep',iproc,istep
!!$      end do
!!$
!!$      call f_free(sendreceive_buffer)
!!$      !if (OP2P%forsymop) then
!!$      call f_free(restemp_buffer)
!!$      !end if
!!$      call f_free(mpireq)
!!$
!!$   END SUBROUTINE OP2P_communication
!!$
!!$
!!$   !> Deallocate everything for OP2P communications
!!$   subroutine free_OP2P_descriptors(OP2P)
!!$     use dynamic_memory
!!$     implicit none
!!$      type(OP2P_descriptors), intent(inout) :: OP2P
!!$
!!$
!!$      call f_free_ptr(OP2P%ngroupp)
!!$      call f_free_ptr(OP2P%nprocgr)
!!$      call f_free_ptr(OP2P%igrpr)
!!$      call f_free_ptr(OP2P%nvctr_par)
!!$      call f_free_ptr(OP2P%ioffp_group)
!!$      call f_free_ptr(OP2P%iprocpm1)
!!$      call f_free_ptr(OP2P%communication_schedule)
!!$
!!$   END SUBROUTINE free_OP2P_descriptors
!!$
!!$
!!$   subroutine wait_mpi(iproc,istep,nreq,requests)
!!$     use wrapper_MPI
!!$      implicit none
!!$      integer, intent(in) :: iproc,istep,nreq
!!$      integer, dimension(nreq), intent(in) :: requests
!!$      !local variables
!!$      integer, dimension(MPI_STATUS_SIZE,4) :: mpistat
!!$      !local variables
!!$      integer :: ierr
!!$
!!$      !verify that the messages have been passed
!!$      call MPI_WAITALL(nreq,requests,mpistat,ierr)
!!$      if (ierr /=0)  then
!!$         write(*,*) 'ERROR WAITALL, iproc,step,ierr:',iproc,istep,ierr,mpistat !,MPI_STATUSES_IGNORE
!!$      end if
!!$   END SUBROUTINE wait_mpi
!!$
!!$
!!$   !> fake receiving of the arrays
!!$   subroutine receive_mpi(istep,isendproc,irecvproc,ncount,itag,irequest,recvbuf)
!!$     use module_base, only: bigdft_mpi,MPI_DOUBLE_PRECISION
!!$      implicit none
!!$      integer, intent(in) :: istep,isendproc,irecvproc,ncount,itag,irequest
!!$      real(kind=8), intent(in) :: recvbuf
!!$      !local variables
!!$      integer :: ierr
!!$
!!$      !here we can add something to trap the IRECV call
!!$      !print '(3(a,i4),i4)','NON_BLOCKING RECV, from',isendproc,' to',irecvproc,', step, elems:',istep,ncount
!!$
!!$      call MPI_IRECV(recvbuf,ncount,MPI_DOUBLE_PRECISION,isendproc,&
!!$         &   itag,bigdft_mpi%mpi_comm,irequest,ierr)
!!$
!!$      !output error signal
!!$      if (ierr /=0) then
!!$         write(*,*)'ERROR in IRECV, iproc, istep',irecvproc,istep
!!$      end if
!!$
!!$   END SUBROUTINE receive_mpi
!!$
!!$   !> fake sending of the arrays
!!$   subroutine send_mpi(istep,irecvproc,ncount,itag,irequest,sendbuf)
!!$     use module_base, only: bigdft_mpi,MPI_DOUBLE_PRECISION
!!$      implicit none
!!$      integer, intent(in) :: istep,irecvproc,ncount,itag,irequest
!!$      real(kind=8), intent(in) :: sendbuf
!!$      !local variables
!!$      integer :: ierr
!!$
!!$      !here we can add something to trap the ISEND call
!!$      !print '(3(a,i4),i4)','NON_BLOCKING SEND, from',isendproc,' to',irecvproc,', step, elems:',istep,ncount
!!$
!!$      call MPI_ISEND(sendbuf,ncount,MPI_DOUBLE_PRECISION,irecvproc,&
!!$         &   itag,bigdft_mpi%mpi_comm,irequest,ierr)
!!$
!!$      !output error signal
!!$      if (ierr /=0) then
!!$         write(*,*)'ERROR in ISEND, iproc, istep',irecvproc,istep
!!$      end if
!!$   END SUBROUTINE send_mpi

END MODULE overlap_point_to_point
