classdef worm
    
    properties
    end
    
    methods
        function set_worm(worm)
            app = Program.app;

            app.worm = worm;

            if isfield(worm, 'body')
                app.BodyDropDown.Value = worm.body;
            end

            if isfield(worm, 'age')
                if any(strcmp(app.AgeDropDown.Items, worm.age))
                    app.AgeDropDown.Value = worm.age;
                else
                    app.AgeDropDown.Value = 'Adult';
                    app.worm.age = 'Adult';
                end
            end

            if isfield(worm, 'sex')
                app.SexDropDown.Value = worm.sex;
            end

            if isfield(worm, 'strain')
                app.StrainEditField.Value = worm.strain;
            end

            if isfield(worm, 'notes')
                app.SubjectNotesTextArea.Value = worm.notes;
            end
        end
    end
end
