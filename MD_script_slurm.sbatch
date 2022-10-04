#!/bin/bash  

#SBATCH --job-name="gromacs"
#SBATCH --output="gromacs.%j.out"
#SBATCH --time=3-00:00:00
#SBATCH --partition=hawkgpu
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=42


source /share/Apps/compilers/etc/lmod/zlmod.sh

module load intel/2021.3.0
module load mpich
module load gromacs/2021.4-cuda-11.6.0
module list

GMXRUN="srun $(which gmx_mpi)"
GMXRUNMPI="srun $(which gmx_mpi)"

#Make the position restraint files.
echo "Make the position restraint files." >&2
${GMXRUN} pdb2gmx -f $1.pdb -o $1_processed.gro -water spce -posrefc 250 -i posre250.itp < pdbgmx.txt
${GMXRUN} pdb2gmx -f $1.pdb -o $1_processed.gro -water spce -posrefc 500 -i posre500.itp < pdbgmx.txt
${GMXRUN} pdb2gmx -f $1.pdb -o $1_processed.gro -water spce -posrefc 750 -i posre750.itp < pdbgmx.txt
${GMXRUN} pdb2gmx -f $1.pdb -o $1_processed.gro -water spce -posrefc 1000 -i posre1000.itp < pdbgmx.txt

#Set the water box configuration
echo "Set the water box configuration" >&2
${GMXRUN} editconf -f $1_processed.gro -o $1_newbox.gro -c -d 1.0 -bt cubic

#Solvate that box
echo "Solvate that box" >&2
${GMXRUN} solvate -cp $1_newbox.gro -cs spc216.gro -o $1_solv.gro -p topol.top


#Add some ions
echo "Add some ions" >&2
${GMXRUN} grompp -f ions.mdp -c $1_solv.gro -r $1_solv.gro -p topol.top -o ions.tpr -maxwarn 4 
${GMXRUN} genion -s ions.tpr -o $1_solv_ions.gro -p topol.top -pname NA -nname CL -neutral < sol.txt


#Minimize the energy
echo "Minimize the energy" >&2
${GMXRUN} grompp -f minim.mdp -c $1_solv_ions.gro -r $1_solv_ions.gro -p topol.top -o em_$1.tpr -maxwarn 4
${GMXRUNMPI} mdrun -v -deffnm em_$1

#Do some energy analysis
#g_energy -f em_$1.edr -o potential.xvg < genergy.txt

#NPT Simulation
echo "NPT Simulation" >&2

#Do a 1 ns equilibration over 4 phases, relaxing the position restraints at each step
echo "grompp -maxwarn 1 -f npt0.mdp -c em_$1.gro -r em_$1.gro -p topol.top -o npt1_$1.tpr" >&2
${GMXRUN} grompp -f npt0.mdp -c em_$1.gro -r em_$1.gro -p topol.top -o npt1_$1.tpr -maxwarn 4
${GMXRUNMPI} mdrun -v -deffnm npt1_$1

cp topol.top ./#topol.top.6#
sed 's/posre1000.itp/posre750.itp/' \#topol.top.6# >topol.top

echo "grompp -f npt.mdp -c npt1_$1.gro -t npt1_$1.trr -p topol.top -o npt2_$1.tpr" >&2
${GMXRUN} grompp -f npt.mdp -c npt1_$1.gro -r npt1_$1.gro -t npt1_$1.trr -p topol.top -o npt2_$1.tpr -maxwarn 4
${GMXRUNMPI} mdrun -v -deffnm npt2_$1

cp topol.top ./#topol.top.7#
sed 's/posre750.itp/posre500.itp/' \#topol.top.7# >topol.top 

echo "grompp -f npt.mdp -c npt2_$1.gro -r npt2_$1.gro -t npt2_$1.trr -p topol.top -o npt3_$1.tpr" >&2
${GMXRUN} grompp -f npt.mdp -c npt2_$1.gro -r npt2_$1.gro -t npt2_$1.trr -p topol.top -o npt3_$1.tpr -maxwarn 4
${GMXRUNMPI} mdrun -v -deffnm npt3_$1 

cp topol.top ./#topol.top.8#
sed 's/posre500.itp/posre250.itp/' \#topol.top.8# >topol.top

echo "grompp -f npt.mdp -c npt3_$1.gro -r npt3_$1.gro -t npt3_$1.trr -p topol.top -o npt4_$1.tpr" >&2
${GMXRUN} grompp -f npt.mdp -c npt3_$1.gro -r npt3_$1.gro -t npt3_$1.trr -p topol.top -o npt4_$1.tpr -maxwarn 4
${GMXRUNMPI} mdrun -v -deffnm npt4_$1

#Profit!
#Now we do the MD simulations
echo "Now we do the MD simulations" >&2

${GMXRUN} grompp -f md.mdp -c npt4_$1.gro -t npt4_$1.trr -p topol.top -o md_$1.tpr -maxwarn 4
${GMXRUNMPI} mdrun -v -deffnm md_$1
date -u;


${GMXRUNMPI} trjconv -f md_$1.trr -o md_$1_fit.pdb -s md_$1.tpr -fit rot+trans < opt.txt
${GMXRUNMPI} trjconv -f md_$1.trr -o md_$1.pdb -s md_$1.tpr < opt.txt

