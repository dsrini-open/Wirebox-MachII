# Wirebox-MachII
Wirebox machII property file configurations

MachII properties for wiring up with wirebox. 

Pre-requisites:
Create wirebox instance in Application or Server scope and provide the scope 
appropriately. 

Wirebox instance could be generated based on the config file as below, 
new wirebox.system.ioc.Injector( 'project.config.wireboxBinder' );

The above line creates the wirebox instance in the Application scope.

MachII property file binds the instances from wirebox within the MachII.