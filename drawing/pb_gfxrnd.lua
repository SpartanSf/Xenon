return {init=function(box,module,api,share,_,load_flags)
    local function check_graphics_mode(terminal)
        if terminal.getGraphicsMode() ~= 1 then
            if not share.set_term_mode then
                api.module_error(module,"Terminal graphics mode must be \"1\"",3,load_flags.supress)
            else terminal.setGraphicsMode(1) end
        end
    end

    local function gfxrnd_renderer(self)
        check_graphics_mode(box.term)
        self.term.drawPixels(
            self.x_offset + 1,
            self.y_offset + 1,
            self.canvas,
            self.width,self.height
        )
    end

    local function gfxrnd_updater()
        local w,h = box.term.getSize(
            box.term.getGraphicsMode and box.term.getGraphicsMode() or 1
        )

        box.term_width,box.term_height = w,h
        box.width,     box.height      = w,h

        api.restore(box,box.background,true,true)
    end

    return {
        render = gfxrnd_renderer
    },{
        verified_load=function()
            if box.term.drawPixels == nil then
                api.module_error(module,"Target terminal doesnt have GFX mode",3,load_flags.supress)
            end

            local w,h = box.term.getSize(1)

            box.term_width,box.term_height = w,h
            box.width,     box.height      = w,h

            if box.modules["PB_MODULE:rndswp"] then
                box.__rndswp__renderer["gfx"] = {
                    drawer = gfxrnd_renderer,
                    update = gfxrnd_updater
                }
            end

            gfxrnd_updater()
        end
    }
end,
    id         = "PB_MODULE:gfxrnd",
    name       = "PB_GFXRender",
    author     = "9551",
    contact    = "https://devvie.cc/contact",
    report_msg = "\n__name: module error, report issues at\n-> __contact"
}